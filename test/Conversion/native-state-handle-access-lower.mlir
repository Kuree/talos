// RUN: talos-opt %s --test-talos-lower-native-state-handle-accesses | FileCheck %s

// Once AOT planning has read the eval bodies' accesses, each access of the
// state a stable handle names becomes the call of its runtime entry, on its
// plane's address and the current context, the call's status unused. A bit a
// read's handle does not name reads as X, 0 in the value plane and 1 in the
// unknown plane (IEEE 1800-2023 7.4.5, 11.5.1). A continuous store calls the
// entry that keeps the contribution for a release (10.6.2). A scalar access
// moves its value through an entry-block temporary live only around the call.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global external @__talos_current_context() : !llvm.ptr
  llvm.func @talos_rt_v1_native_state_load_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, i32, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_native_state_store_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_native_state_store_continuous_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_native_frame_store(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i32, i32, i64, i64)
  llvm.func @talos_rt_v1_native_frame_store_wide(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i32, i32, !llvm.ptr, !llvm.ptr)

  // CHECK-LABEL: llvm.func @load_bytes(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]] {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(7 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%{{.*}}, %[[BASE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: llvm.return
  llvm.func @load_bytes(%handle: i64, %buffer: !llvm.ptr) {
    schedule.state.load_handle_bytes @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 7 : i64}
    schedule.state.load_handle_bytes @__talos_state_unknown[%handle] into %buffer {state_bits = 128 : i64, width = 7 : i64}
    llvm.return
  }

  // CHECK-LABEL: llvm.func @store_bytes(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr, %[[CHANGED:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(200 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[BUFFER]], %[[CHANGED]])
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_continuous_plane(%{{.*}}, %[[BASE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[PLANE]], %[[BUFFER]], %[[CHANGED]])
  // CHECK-NEXT: llvm.return
  llvm.func @store_bytes(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    schedule.state.store_handle_bytes %buffer, @__talos_state_unknown[%handle] changed %changed {state_bits = 128 : i64, width = 200 : i64}
    schedule.state.store_handle_bytes %buffer, @__talos_state_value[%handle] changed %changed continuous {state_bits = 128 : i64, width = 200 : i64}
    llvm.return
  }

  // A scalar read passes a temporary for the runtime to write and reads its
  // value from it.
  // CHECK-LABEL: llvm.func @load(
  // CHECK-SAME: %[[HANDLE:.*]]: i64)
  // CHECK-NEXT: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[OUT:.*]] = llvm.alloca %[[COUNT]] x i7 {alignment = 1 : i64}
  // CHECK-NEXT: llvm.intr.lifetime.start %[[OUT]]
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(7 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[FALLBACK]], %[[OUT]])
  // CHECK-NEXT: %[[LOADED:.*]] = llvm.load %[[OUT]] {alignment = 1 : i64} : !llvm.ptr -> i7
  // CHECK-NEXT: llvm.intr.lifetime.end %[[OUT]]
  // CHECK-NEXT: llvm.return %[[LOADED]] : i7
  llvm.func @load(%handle: i64) -> i7 {
    %value = schedule.state.load_handle @__talos_state_unknown[%handle] {state_bits = 128 : i64} : i7
    llvm.return %value : i7
  }

  // CHECK-LABEL: llvm.func @load_value(
  // CHECK: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%{{.*}}, %[[BASE]], %{{.*}}, %{{.*}}, %{{.*}}, %[[PLANE]], %[[FALLBACK]], %[[OUT:[^)]*]])
  // CHECK-NEXT: %[[LOADED:.*]] = llvm.load %[[OUT]] {alignment = 1 : i64} : !llvm.ptr -> i65
  // CHECK-NEXT: llvm.intr.lifetime.end %[[OUT]]
  // CHECK-NEXT: llvm.return %[[LOADED]] : i65
  llvm.func @load_value(%handle: i64) -> i65 {
    %value = schedule.state.load_handle @__talos_state_value[%handle] {state_bits = 128 : i64} : i65
    llvm.return %value : i65
  }

  // A scalar write passes its value in one temporary and a change byte,
  // cleared before the call, in another; it changed the state when the
  // runtime set that byte (IEEE 1800-2023 9.4.2).
  // CHECK-LABEL: llvm.func @store(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: i200)
  // CHECK-NEXT: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[CHANGED:.*]] = llvm.alloca %[[COUNT]] x i8 {alignment = 1 : i64}
  // CHECK-NEXT: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[IN:.*]] = llvm.alloca %[[COUNT]] x i200 {alignment = 1 : i64}
  // CHECK-NEXT: llvm.intr.lifetime.start %[[IN]]
  // CHECK-NEXT: llvm.store %[[VALUE]], %[[IN]] {alignment = 1 : i64} : i200, !llvm.ptr
  // CHECK-NEXT: llvm.intr.lifetime.start %[[CHANGED]]
  // CHECK-NEXT: %[[CLEAR:.*]] = llvm.mlir.constant(0 : i8) : i8
  // CHECK-NEXT: llvm.store %[[CLEAR]], %[[CHANGED]] {alignment = 1 : i64} : i8, !llvm.ptr
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(200 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_continuous_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[IN]], %[[CHANGED]])
  // CHECK-NEXT: %[[BYTE:.*]] = llvm.load %[[CHANGED]] {alignment = 1 : i64} : !llvm.ptr -> i8
  // CHECK-NEXT: llvm.intr.lifetime.end %[[IN]]
  // CHECK-NEXT: llvm.intr.lifetime.end %[[CHANGED]]
  // CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i8) : i8
  // CHECK-NEXT: %[[RESULT:.*]] = arith.cmpi ne, %[[BYTE]], %[[ZERO]] : i8
  // CHECK-NEXT: llvm.return %[[RESULT]] : i1
  llvm.func @store(%handle: i64, %value: i200) -> i1 {
    %changed = schedule.state.store_handle %value, @__talos_state_value[%handle] continuous {state_bits = 128 : i64} : i200
    llvm.return %changed : i1
  }

  // CHECK-LABEL: llvm.func @store_unknown(
  // CHECK: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_plane(%{{.*}}, %[[BASE]], %{{.*}}, %{{.*}}, %{{.*}}, %[[PLANE]], %{{.*}}, %{{.*}})
  // CHECK: %[[RESULT:.*]] = arith.cmpi ne
  // CHECK-NEXT: llvm.return %[[RESULT]] : i1
  llvm.func @store_unknown(%handle: i64, %value: i8) -> i1 {
    %changed = schedule.state.store_handle %value, @__talos_state_unknown[%handle] {state_bits = 128 : i64} : i8
    llvm.return %changed : i1
  }

  // A frame store passes the planes it writes, both of a four-state
  // destination, and its value and X/Z bits as words; the flags name a
  // continuous contribution (1) and a four-state destination (2). A
  // two-state destination passes no unknown plane and no X/Z bits.
  // CHECK-LABEL: llvm.func @frame(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: i7, %[[UNKNOWN:.*]]: i7)
  // CHECK-NEXT: %[[VALUE_PLANE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[UNKNOWN_PLANE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK-NEXT: %[[UNKNOWN_WORD:.*]] = arith.extui %[[UNKNOWN]] : i7 to i64
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(7 : i32) : i32
  // CHECK-NEXT: %[[FLAGS:.*]] = llvm.mlir.constant(3 : i32) : i32
  // CHECK-NEXT: %[[VALUE_WORD:.*]] = arith.extui %[[VALUE]] : i7 to i64
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_frame_store(%[[CONTEXT]], %[[VALUE_PLANE]], %[[UNKNOWN_PLANE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[FLAGS]], %[[VALUE_WORD]], %[[UNKNOWN_WORD]])
  // CHECK-NEXT: schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[NO_PLANE:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: %[[NO_UNKNOWN:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK: %[[TWO_STATE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK: llvm.call @talos_rt_v1_native_frame_store(%{{.*}}, %{{.*}}, %[[NO_PLANE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[TWO_STATE]], %{{.*}}, %[[NO_UNKNOWN]])
  // CHECK-NEXT: llvm.return
  llvm.func @frame(%handle: i64, %value: i7, %unknown: i7) {
    schedule.state.frame_store %value, %unknown to %handle four_state continuous {state_bits = 128 : i64} : i7, i7
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i7
    llvm.return
  }

  // Wider assignments publish all limbs in a single runtime call. An
  // omitted unknown input is an implicit zero buffer.
  // CHECK-LABEL: llvm.func @wide_frame(
  // CHECK: llvm.store %{{.*}}, %[[V:.*]] {alignment = 1 : i64} : i129, !llvm.ptr
  // CHECK: llvm.store %{{.*}}, %[[U:.*]] {alignment = 1 : i64} : i129, !llvm.ptr
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_frame_store_wide(%{{.*}}, %[[V]], %[[U]])
  // CHECK: %[[KNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_frame_store_wide(%{{.*}}, %[[KNOWN]])
  llvm.func @wide_frame(%handle: i64, %value: i129, %unknown: i129) {
    schedule.state.frame_store %value, %unknown to %handle four_state {state_bits = 256 : i64} : i129, i129
    schedule.state.frame_store %value to %handle four_state {state_bits = 256 : i64} : i129
    llvm.return
  }

  // A four-state destination written without X/Z bits passes its unknown
  // plane and an unknown word of 0; a two-state continuous contribution sets
  // only the continuous flag.
  // CHECK-LABEL: llvm.func @frame_flags(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: i7)
  // CHECK-NEXT: %[[VALUE_PLANE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[UNKNOWN_PLANE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK-NEXT: %[[KNOWN:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(7 : i32) : i32
  // CHECK-NEXT: %[[FOUR_STATE:.*]] = llvm.mlir.constant(2 : i32) : i32
  // CHECK-NEXT: %[[VALUE_WORD:.*]] = arith.extui %[[VALUE]] : i7 to i64
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_frame_store(%[[CONTEXT]], %[[VALUE_PLANE]], %[[UNKNOWN_PLANE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[FOUR_STATE]], %[[VALUE_WORD]], %[[KNOWN]])
  // CHECK-NEXT: %[[VALUE_PLANE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[NO_PLANE:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: %[[NO_UNKNOWN:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK: %[[CONTINUOUS:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: %[[VALUE_WORD:.*]] = arith.extui %[[VALUE]] : i7 to i64
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_frame_store(%{{.*}}, %[[VALUE_PLANE]], %[[NO_PLANE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[CONTINUOUS]], %[[VALUE_WORD]], %[[NO_UNKNOWN]])
  // CHECK-NEXT: llvm.return
  llvm.func @frame_flags(%handle: i64, %value: i7) {
    schedule.state.frame_store %value to %handle four_state {state_bits = 128 : i64} : i7
    schedule.state.frame_store %value to %handle continuous {state_bits = 128 : i64} : i7
    llvm.return
  }

  // An access in a later block keeps its temporary in the entry block, a
  // static alloca, live only around the call.
  // CHECK-LABEL: llvm.func @nested(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %{{.*}}: i1)
  // CHECK-NEXT: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[OUT:.*]] = llvm.alloca %[[COUNT]] x i7 {alignment = 1 : i64}
  // CHECK-NEXT: llvm.cond_br
  // CHECK-NEXT: ^{{.*}}:
  // CHECK-NEXT: llvm.intr.lifetime.start %[[OUT]]
  // CHECK: llvm.call @talos_rt_v1_native_state_load_plane(%{{.*}}, %{{.*}}, %{{.*}}, %[[HANDLE]], %{{.*}}, %{{.*}}, %{{.*}}, %[[OUT]])
  // CHECK-NEXT: %[[LOADED:.*]] = llvm.load %[[OUT]] {alignment = 1 : i64} : !llvm.ptr -> i7
  // CHECK-NEXT: llvm.intr.lifetime.end %[[OUT]]
  // CHECK-NEXT: llvm.br ^{{.*}}(%[[LOADED]] : i7)
  llvm.func @nested(%handle: i64, %read: i1) -> i7 {
    llvm.cond_br %read, ^read, ^skip
  ^read:
    %value = schedule.state.load_handle @__talos_state_value[%handle] {state_bits = 128 : i64} : i7
    llvm.br ^done(%value : i7)
  ^skip:
    %zero = llvm.mlir.constant(0 : i7) : i7
    llvm.br ^done(%zero : i7)
  ^done(%result: i7):
    llvm.return %result : i7
  }

  // An automatic variable's read names its context and passes its buffer for
  // the plane of no design state; a bit outside the variable reads 0. Its
  // status is the call's.
  // CHECK-LABEL: llvm.func @automatic(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(65 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[STATUS:.*]] = llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[BUFFER]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: llvm.return %[[STATUS]]
  llvm.func @automatic(%context: !llvm.ptr, %handle: i64, %buffer: !llvm.ptr) -> i32 {
    %status = schedule.state.load_automatic %context, %handle into %buffer unknown {width = 65 : i64}
    llvm.return %status : i32
  }

  // CHECK-LABEL: llvm.func @automatic_value(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(8 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[STATUS:.*]] = llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[BUFFER]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: llvm.return %[[STATUS]]
  llvm.func @automatic_value(%context: !llvm.ptr, %handle: i64, %buffer: !llvm.ptr) -> i32 {
    %status = schedule.state.load_automatic %context, %handle into %buffer {width = 8 : i64}
    llvm.return %status : i32
  }
}
