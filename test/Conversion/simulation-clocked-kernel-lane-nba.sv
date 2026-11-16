// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 7.4.1, 7.4.5, 10.4.2, 11.5.1: the selected packed
// lane is an enclosing boundary. Partial overlap updates only that lane;
// an invalid/X lane selects no storage. A dynamic whole-root range fact is
// a may-select hull, not proof that the inner select may cross lane bounds.
// CHECK-LABEL: simulation.func private @{{__talos_clocked_[0-9_]+}}(
// CHECK: %[[LANE:.*]] = simulation.ref.array_element
// CHECK-SAME: -> !simulation.ref<!simulation.packed_array<126 : 0 x !simulation.logic<1>>>
// CHECK: %[[PART:.*]] = simulation.ref.dyn_extract %[[LANE]] from
// CHECK-NEXT: simulation.nba.enqueue %{{.*}} to %[[PART]]
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

module top;
  bit clk;
  logic signed [31:0] row;
  logic signed [63:0] idx;
  logic [7:0] d;
  logic [2:0][126:0] q;
  logic [380:0] old_q;
  always #5 clk = !clk;
  always @(posedge clk) q[row][idx +: 8] <= d;
  always @(posedge clk) old_q <= q;
  initial #7 $display("%b %b", q, old_q);
endmodule
