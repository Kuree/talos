// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 clocked-kernels=off stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 clocked-kernels=off' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 11.5.1: normalize both declaration directions in a wider
// signed type before constructing the captured NBA view. In particular, an
// extreme i64 index must not wrap during subtraction of a negative bound.
// CHECK-LABEL: simulation.func private @{{__talos_fused_[0-9_]+}}.__talos_eval_body_0(
// CHECK: %[[DOWN_INDEX:.*]] = simulation.logic.resize %{{.*}} signed = true {{.*}} : !simulation.logic<64> -> !simulation.logic<66>
// CHECK: %[[DOWN_BOUND:.*]] = simulation.logic.constant -17 : i66
// CHECK: %[[DOWN_LOW:.*]] = simulation.logic.binary sub %[[DOWN_INDEX]], %[[DOWN_BOUND]]
// CHECK: %[[DOWN_VIEW:.*]] = simulation.ref.dyn_extract %{{.*}} from %[[DOWN_LOW]]
// CHECK-SAME: !simulation.packed_array<-1 : -17 x !simulation.logic<1>>
// CHECK: simulation.nba.enqueue %{{.*}} to %[[DOWN_VIEW]]
// CHECK: %[[UP_INDEX:.*]] = simulation.logic.resize %{{.*}} signed = true {{.*}} : !simulation.logic<64> -> !simulation.logic<66>
// CHECK: %[[UP_BOUND:.*]] = simulation.logic.constant -1 : i66
// CHECK: %[[UP_LOW:.*]] = simulation.logic.binary sub %[[UP_BOUND]], %[[UP_INDEX]]
// CHECK: %[[UP_VIEW:.*]] = simulation.ref.dyn_extract %{{.*}} from %[[UP_LOW]]
// CHECK-SAME: !simulation.packed_array<-17 : -1 x !simulation.logic<1>>
// CHECK: simulation.nba.enqueue %{{.*}} to %[[UP_VIEW]]
// CHECK: simulation.return
//
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic signed [63:0] idx = 64'h8000000000000011;
  logic [-1:-17] down = 17'h15555;
  logic [-17:-1] up = 17'h0aaaa;
  always #5 clk = !clk;
  always @(posedge clk) down[idx +: 8] <= 0;
  always @(posedge clk) up[idx -: 8] <= '1;
endmodule
