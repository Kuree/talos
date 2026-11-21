// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval' --mlir-print-ir-after=prepare-native-fragments -o %t.mlir 2> %t.fragments
// RUN: FileCheck %s --check-prefix=TYPED < %t.fragments
// RUN: FileCheck %s --check-prefix=CALL < %t.mlir

// The first always_comb runs as a ranked process across the clock's Active
// handoff, and its indexed part-select write has no fixed root, so native
// lowering writes it as one frame store: both planes of the four bits change
// before the single value-change publication (IEEE 1800-2023 9.4.2, 11.5.1),
// and the contribution is kept for a release (10.6.2). AOT planning leaves it
// to the runtime, which receives the value and its X/Z bits as words.
module top;
  logic left, right, left_enable, right_enable, seen_left, seen_right;
  logic [15:0] state;
  logic [3:0] source, idx;
  bit clk;
  int ticks, falling_edges;
  always #2 clk = !clk;
  always_ff @(posedge clk) ticks <= ticks + 1;
  always_comb begin
    seen_right = right;
    state[idx +: 4] = source;
    left = 0;
    left = left_enable;
  end
  always_comb begin
    seen_left = left;
    right = 0;
    right = right_enable;
  end
  always @(negedge left or negedge right) falling_edges++;
  initial begin
    idx = 4;
    source = 4'bx1z0;
    #1 left_enable = 1;
    right_enable = 1;
    #5 $display("state %b", state[7:4]);
  end
endmodule

// TYPED-LABEL: IR Dump After PrepareNativeFragmentsPass
// TYPED: schedule.state.frame_store %{{.*}}, %{{.*}} to %{{.*}} four_state continuous {state_bits = {{[0-9]+}} : i64} : i4, i4
// TYPED-NOT: llvm.call @talos_rt_v1_native_frame_store

// CALL-NOT: schedule.state.frame_store
// CALL: %[[UNKNOWN:.*]] = llvm.zext %{{.*}} : i4 to i64
// CALL-NEXT: %[[CONTEXT:.*]] = llvm.load
// CALL-NEXT: %[[VALUE:.*]] = llvm.zext %{{.*}} : i4 to i64
// CALL-NEXT: llvm.call @talos_rt_v1_native_frame_store(%[[CONTEXT]], %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %[[VALUE]], %[[UNKNOWN]])
// CALL-NOT: schedule.state.frame_store
