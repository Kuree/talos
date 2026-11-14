// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(raise-native-state-access))' | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(raise-native-state-access,lower-native-state-access,cse))' | FileCheck %s --check-prefix=ROUND

// A plain LLVM load or store of a state plane's address, or of one byte GEP
// of it, becomes a typed access; the tags producers put on it become its
// properties. An access the typed operations cannot express stays as it is,
// as does a plane address outside a function.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  // CHECK: llvm.mlir.global internal @descriptor()
  // CHECK: llvm.mlir.addressof @__talos_state_value
  llvm.mlir.global internal @descriptor() : !llvm.ptr {
    %a = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    llvm.return %a : !llvm.ptr
  }
  llvm.func @use(!llvm.ptr)

  // Offsets: a constant index, an SSA constant, offset zero through the base
  // itself, and an i64 dynamic index. The raised GEPs and the unused unknown
  // base disappear; the value base stays for its call.
  // CHECK-LABEL: llvm.func @offsets(
  // CHECK-SAME: %[[V:.*]]: i32, %[[U:.*]]: i8, %[[D:.*]]: i64)
  // CHECK-NOT: llvm.getelementptr
  // CHECK-NOT: @__talos_state_unknown :
  // CHECK: %[[BASE:.*]] = schedule.state.address @__talos_state_value : !llvm.ptr
  // CHECK: schedule.state.load @__talos_state_value[4] {alignment = 4 : i64} : i32
  // CHECK-NEXT: schedule.state.store %[[U]], @__talos_state_unknown[12] {alignment = 1 : i64} : i8
  // CHECK-NEXT: schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
  // CHECK-NEXT: schedule.state.store %[[U]], @__talos_state_unknown[0] {alignment = 1 : i64} : i8
  // CHECK-NEXT: schedule.state.store %[[U]], @__talos_state_unknown[%[[D]]] {alignment = 1 : i64} : i8
  // CHECK-NEXT: llvm.call @use(%[[BASE]])
  // ROUND-LABEL: llvm.func @offsets(
  // ROUND-NOT: schedule.state
  // ROUND: llvm.return
  llvm.func @offsets(%v: i32, %u: i8, %d: i64) -> i32 {
    %value = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %unknown = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
    %twelve = llvm.mlir.constant(12 : i64) : i64
    %p4 = llvm.getelementptr %value[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %x = llvm.load %p4 {alignment = 4 : i64} : !llvm.ptr -> i32
    %p12 = llvm.getelementptr %unknown[%twelve] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %u, %p12 {alignment = 1 : i64} : i8, !llvm.ptr
    %z = llvm.load %value {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.store %u, %unknown {alignment = 1 : i64} : i8, !llvm.ptr
    %pd = llvm.getelementptr %unknown[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %u, %pd {alignment = 1 : i64} : i8, !llvm.ptr
    llvm.call @use(%value) : (!llvm.ptr) -> ()
    llvm.return %x : i32
  }

  // Tags become properties.
  // CHECK-LABEL: llvm.func @tags(
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_unknown[%{{.*}}] {alignment = 1 : i64, owner = 2 : i32, summary_reported, window = array<i64: 0, 16>, written_bits = array<i64: 3, 5>} : i8
  // CHECK: schedule.state.load @__talos_state_unknown[8] {alignment = 1 : i64, latch_destination, owner = 1 : i32, window = array<i64: 8, 9>} : i8
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[8] {alignment = 1 : i64, latch_destination} : i8
  llvm.func @tags(%u: i8, %d: i64) -> i8 {
    %value = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %unknown = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
    %pd = llvm.getelementptr %unknown[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %u, %pd {alignment = 1 : i64, schedule.eval.state_access_bytes = array<i64: 0, 16>, schedule.eval.unknown_write_range = array<i64: 3, 5>, schedule.eval.unknown_summary_reported, schedule.eval.group_owner = 2 : i32} : i8, !llvm.ptr
    %p8 = llvm.getelementptr %unknown[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %l = llvm.load %p8 {alignment = 1 : i64, schedule.eval.preserve_nba_unknown, schedule.eval.group_owner = 1 : i32, schedule.eval.state_access_bytes = array<i64: 8, 9>} : !llvm.ptr -> i8
    %v8 = llvm.getelementptr %value[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %l, %v8 {alignment = 1 : i64, schedule.eval.preserve_nba_unknown} : i8, !llvm.ptr
    llvm.return %l : i8
  }

  // Accesses the typed operations cannot express stay LLVM accesses, and the
  // GEPs and plane address they use stay with them: another tag, a write
  // range or summary report on a load, a malformed window, written-bit range
  // or owner, a volatile access, a negative or i32 index, an inbounds GEP, a
  // word-indexed GEP, a chain of GEPs, and a tagged plane address.
  // CHECK-LABEL: llvm.func @kept(
  // CHECK: %[[VALUE:.*]] = schedule.state.address @__talos_state_value
  // CHECK: llvm.load %{{.*}} {alignment = 1 : i64, schedule.eval.activation_entry = 1 : i32} : !llvm.ptr -> i8
  // CHECK: llvm.load %{{.*}} {alignment = 1 : i64, schedule.eval.unknown_write_range = array<i64: 0, 8>} : !llvm.ptr -> i8
  // CHECK: llvm.load %{{.*}} {alignment = 1 : i64, schedule.eval.unknown_summary_reported} : !llvm.ptr -> i8
  // CHECK: llvm.load %{{.*}} {alignment = 1 : i64, schedule.eval.state_access_bytes = array<i64: 8, 4>} : !llvm.ptr -> i8
  // CHECK: llvm.store %{{.*}}, %{{.*}} {alignment = 1 : i64, schedule.eval.unknown_write_range = array<i64: 8, 0>} : i8, !llvm.ptr
  // CHECK: llvm.load %{{.*}} {alignment = 1 : i64, schedule.eval.group_owner = 2 : i64} : !llvm.ptr -> i8
  // CHECK: llvm.load volatile
  // CHECK: llvm.getelementptr %[[VALUE]][-1]
  // CHECK: llvm.getelementptr %[[VALUE]][%{{.*}}] : (!llvm.ptr, i32)
  // CHECK: llvm.getelementptr inbounds %[[VALUE]][2]
  // CHECK: llvm.getelementptr %[[VALUE]][%{{.*}}] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK: %[[OUTER:.*]] = llvm.getelementptr %[[VALUE]][%{{.*}}] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.getelementptr %[[OUTER]][8]
  // CHECK: llvm.mlir.addressof @__talos_state_unknown {test.tag} : !llvm.ptr
  llvm.func @kept(%d: i64, %w: i32) -> i8 {
    %value = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %p1 = llvm.getelementptr %value[1] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %p1 {alignment = 1 : i64, schedule.eval.activation_entry = 1 : i32} : !llvm.ptr -> i8
    %b = llvm.load %p1 {alignment = 1 : i64, schedule.eval.unknown_write_range = array<i64: 0, 8>} : !llvm.ptr -> i8
    %c = llvm.load %p1 {alignment = 1 : i64, schedule.eval.unknown_summary_reported} : !llvm.ptr -> i8
    %e = llvm.load %p1 {alignment = 1 : i64, schedule.eval.state_access_bytes = array<i64: 8, 4>} : !llvm.ptr -> i8
    llvm.store %e, %p1 {alignment = 1 : i64, schedule.eval.unknown_write_range = array<i64: 8, 0>} : i8, !llvm.ptr
    %f = llvm.load %p1 {alignment = 1 : i64, schedule.eval.group_owner = 2 : i64} : !llvm.ptr -> i8
    %g = llvm.load volatile %p1 {alignment = 1 : i64} : !llvm.ptr -> i8
    %pn = llvm.getelementptr %value[-1] : (!llvm.ptr) -> !llvm.ptr, i8
    %h = llvm.load %pn {alignment = 1 : i64} : !llvm.ptr -> i8
    %pw = llvm.getelementptr %value[%w] : (!llvm.ptr, i32) -> !llvm.ptr, i8
    %i = llvm.load %pw {alignment = 1 : i64} : !llvm.ptr -> i8
    %pb = llvm.getelementptr inbounds %value[2] : (!llvm.ptr) -> !llvm.ptr, i8
    %j = llvm.load %pb {alignment = 1 : i64} : !llvm.ptr -> i8
    %pk = llvm.getelementptr %value[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %k = llvm.load %pk {alignment = 8 : i64} : !llvm.ptr -> i64
    %po = llvm.getelementptr %value[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pi = llvm.getelementptr %po[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %m = llvm.load %pi {alignment = 1 : i64} : !llvm.ptr -> i8
    %tagged = llvm.mlir.addressof @__talos_state_unknown {test.tag} : !llvm.ptr
    %n = llvm.load %tagged {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.return %n : i8
  }
}
