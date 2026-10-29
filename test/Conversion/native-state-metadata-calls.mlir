// RUN: talos-opt %s --address-native-state-through-bases -o %t.mlir
// RUN: FileCheck %s --check-prefix=IR < %t.mlir
// RUN: talos-opt %t.mlir --address-native-state-through-bases | diff %t.mlir -
// RUN: talos-opt %s --mlir-disable-threading --address-native-state-through-bases | diff %t.mlir -
// RUN: talos-translate --mlir-to-llvmir %t.mlir | %llvm_dist/bin/opt -S -passes='default<O3>' -o %t.ll
// RUN: FileCheck %s --check-prefix=OPT < %t.ll

// The generated publication proof excludes physical state, while retaining
// writes to proof metadata. An opaque descendant models a separate native
// partition: LLVM cannot infer its effects from a definition here. The runtime
// companion checks publication counts, aliasing and overlapping stores under
// both optimization paths (LRM 4.6/6.3.1).
#domain = #llvm.alias_scope_domain<id = "existing">
#old = #llvm.alias_scope<id = "old", domain = #domain>
#other = #llvm.alias_scope<id = "other", domain = #domain>
module attributes {llvm.data_layout = "e-p:64:64-i64:64-n8:16:32:64"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @metadata(0 : i8) : i8
  llvm.func @metadata_sink(!llvm.ptr)
  llvm.func @state_sink(!llvm.ptr, i8)

  llvm.func @publish_metadata() attributes {passthrough = ["noinline"], schedule.eval.state_metadata_only} {
    %p = llvm.mlir.addressof @metadata : !llvm.ptr
    llvm.call @metadata_sink(%p) : (!llvm.ptr) -> ()
    llvm.return
  }

  // Both planes may be reused across publication, without removing the call.
  // IR-LABEL: llvm.func @reuse_both
  // IR: alias_scopes = [#[[V:alias_scope[0-9]*]]]
  // IR: alias_scopes = [#[[X:alias_scope[0-9]*]]]
  // IR: llvm.call @publish_metadata() {{.*}}noalias_scopes = [#[[V]], #[[X]]]
  // OPT-LABEL: define {{.*}}@reuse_both(
  // OPT-COUNT-2: load i8,
  // OPT-NOT: load i8,
  // OPT: ret i8
  llvm.func @reuse_both() -> i8 attributes {passthrough = ["noinline"]} {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %xp = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
    %v0 = llvm.load %vp : !llvm.ptr -> i8
    %x0 = llvm.load %xp : !llvm.ptr -> i8
    llvm.call @publish_metadata() : () -> ()
    %v1 = llvm.load %vp : !llvm.ptr -> i8
    %x1 = llvm.load %xp : !llvm.ptr -> i8
    %a = llvm.add %v0, %x0 : i8
    %b = llvm.add %v1, %x1 : i8
    %sum = llvm.add %a, %b : i8
    llvm.return %sum : i8
  }

  // Publication really writes metadata; it is not readnone or removable.
  // OPT-LABEL: define {{.*}}@metadata_effect(
  // OPT: load i8, ptr @metadata
  // OPT: call void @publish_metadata()
  // OPT: load i8, ptr @metadata
  // OPT: ret i8
  llvm.func @metadata_effect() -> i8 attributes {passthrough = ["noinline"]} {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %mp = llvm.mlir.addressof @metadata : !llvm.ptr
    %v = llvm.load %vp : !llvm.ptr -> i8
    %before = llvm.load %mp : !llvm.ptr -> i8
    llvm.call @publish_metadata() : () -> ()
    %after = llvm.load %mp : !llvm.ptr -> i8
    %sum = llvm.add %before, %after : i8
    %result = llvm.add %sum, %v : i8
    llvm.return %result : i8
  }

  // An unproved call may write either plane, so its reload remains required.
  // IR-LABEL: llvm.func @opaque_writer
  // IR: llvm.call @state_sink
  // IR-NOT: noalias_scopes
  // IR: llvm.call @publish_metadata() {{.*}}noalias_scopes
  // OPT-LABEL: define {{.*}}@opaque_writer(
  // OPT: load i8,
  // OPT: call void @state_sink
  // OPT: load i8,
  // OPT: ret i8
  llvm.func @opaque_writer(%p: !llvm.ptr, %value: i8) -> i8 attributes {passthrough = ["noinline"]} {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %before = llvm.load %vp : !llvm.ptr -> i8
    llvm.call @state_sink(%p, %value) : (!llvm.ptr, i8) -> ()
    llvm.call @publish_metadata() : () -> ()
    %after = llvm.load %vp : !llvm.ptr -> i8
    %sum = llvm.add %before, %after : i8
    llvm.return %sum : i8
  }

  // Scopes do not separate overlapping accesses within one plane.
  // OPT-LABEL: define {{.*}}@overlap(
  // OPT: load i16,
  // OPT: store i8
  // OPT: load i16,
  // OPT: ret i16
  llvm.func @overlap(%c: i1, %byte: i8) -> i16 attributes {passthrough = ["noinline"]} {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %before = llvm.load %vp : !llvm.ptr -> i16
    llvm.cond_br %c, ^update, ^done
  ^update:
    llvm.store %byte, %vp : i8, !llvm.ptr
    llvm.br ^done
  ^done:
    llvm.call @publish_metadata() : () -> ()
    %after = llvm.load %vp : !llvm.ptr -> i16
    %sum = llvm.add %before, %after : i16
    llvm.return %sum : i16
  }

  // Constant byte offsets may be static GEP indices or SSA constants. Their
  // summed offset and the entire access must fit the physical allocation.
  // IR-LABEL: llvm.func @bounded_offsets
  // IR: llvm.load {{.*}}alias_scopes
  // IR: llvm.call @publish_metadata() {{.*}}noalias_scopes
  // OPT-LABEL: define {{.*}}@bounded_offsets(
  // OPT: load i16,
  // OPT-NOT: load i16,
  // OPT: ret i16
  llvm.func @bounded_offsets() -> i16 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %seven = llvm.mlir.constant(7 : i64) : i64
    %a = llvm.getelementptr %vp[1] : (!llvm.ptr) -> !llvm.ptr, i8
    %p = llvm.getelementptr %a[%seven] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %before = llvm.load %p {alignment = 1 : i64} : !llvm.ptr -> i16
    llvm.call @publish_metadata() : () -> ()
    %after = llvm.load %p {alignment = 1 : i64} : !llvm.ptr -> i16
    %sum = llvm.add %before, %after : i16
    llvm.return %sum : i16
  }

  // Preserve preexisting scopes rather than replacing a caller's metadata.
  // IR-LABEL: llvm.func @existing_scopes
  // IR: alias_scopes = [#{{[^,]*}}, #{{[^]]*}}]
  // IR: noalias_scopes = [#{{[^,]*}}, #{{[^,]*}}, #{{[^]]*}}]
  llvm.func @existing_scopes() -> i8 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %v = llvm.load %vp {alias_scopes = [#old]} : !llvm.ptr -> i8
    llvm.call @publish_metadata() {noalias_scopes = [#other]} : () -> ()
    llvm.return %v : i8
  }

  // No whole-plane promise for unknown, negative, past-end or straddling
  // addresses, or for an arbitrary pointer argument.
  // IR-LABEL: llvm.func @unproved_addresses
  // IR-NOT: alias_scopes
  // IR-NOT: noalias_scopes
  // IR: llvm.return
  llvm.func @unproved_addresses(%index: i64, %p: !llvm.ptr) -> i16 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %dynamic = llvm.getelementptr %vp[%index] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %negative = llvm.getelementptr %vp[-1] : (!llvm.ptr) -> !llvm.ptr, i8
    %past = llvm.getelementptr %vp[64] : (!llvm.ptr) -> !llvm.ptr, i8
    %end = llvm.getelementptr %vp[63] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %dynamic : !llvm.ptr -> i16
    llvm.store %a, %negative : i16, !llvm.ptr
    llvm.store %a, %past : i16, !llvm.ptr
    llvm.store %a, %end : i16, !llvm.ptr
    llvm.call @publish_metadata() : () -> ()
    %b = llvm.load %p : !llvm.ptr -> i16
    llvm.return %b : i16
  }

  llvm.func @main() -> i32 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %xp = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
    %five = llvm.mlir.constant(5 : i8) : i8
    %nine = llvm.mlir.constant(9 : i8) : i8
    %seven = llvm.mlir.constant(7 : i8) : i8
    llvm.store %five, %vp : i8, !llvm.ptr
    llvm.store %nine, %xp : i8, !llvm.ptr
    // Keep both plane addresses escaped to the opaque external writer.
    llvm.call @state_sink(%xp, %nine) : (!llvm.ptr, i8) -> ()
    %sum = llvm.call @reuse_both() : () -> i8
    %twenty_eight = llvm.mlir.constant(28 : i8) : i8
    %a = llvm.icmp "eq" %sum, %twenty_eight : i8
    %effects = llvm.call @metadata_effect() : () -> i8
    %eight = llvm.mlir.constant(8 : i8) : i8
    %b = llvm.icmp "eq" %effects, %eight : i8
    %aliased = llvm.call @opaque_writer(%vp, %seven) : (!llvm.ptr, i8) -> i8
    %twelve = llvm.mlir.constant(12 : i8) : i8
    %c = llvm.icmp "eq" %aliased, %twelve : i8
    %word = llvm.mlir.constant(4660 : i16) : i16
    %byte = llvm.mlir.constant(86 : i8) : i8
    %yes = llvm.mlir.constant(true) : i1
    llvm.store %word, %vp : i16, !llvm.ptr
    %overlapped = llvm.call @overlap(%yes, %byte) : (i1, i8) -> i16
    %expected = llvm.mlir.constant(9354 : i16) : i16
    %d = llvm.icmp "eq" %overlapped, %expected : i16
    %mp = llvm.mlir.addressof @metadata : !llvm.ptr
    %published = llvm.load %mp : !llvm.ptr -> i8
    %four = llvm.mlir.constant(4 : i8) : i8
    %e = llvm.icmp "eq" %published, %four : i8
    %ab = llvm.and %a, %b : i1
    %cd = llvm.and %c, %d : i1
    %abcd = llvm.and %ab, %cd : i1
    %all = llvm.and %abcd, %e : i1
    %zero = llvm.mlir.constant(0 : i32) : i32
    %one = llvm.mlir.constant(1 : i32) : i32
    %result = llvm.select %all, %zero, %one : i1, i32
    llvm.return %result : i32
  }
}
