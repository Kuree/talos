// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 clocked-kernels=immediate stop-after=lowering' | FileCheck %s --check-prefix=IMMEDIATE
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.9.4, 10.4.2, 11.5.1: an NBA destination may overhang
// its input root, whereas ref.store cannot represent that clipping contract.
// Deferred fusion retains both overhanging NBAs and turns only their sibling
// captures into stores. Immediate mode retains all four NBAs in its fused
// eval body. Cover scalar and multiword roots.
// CHECK-LABEL: simulation.func private @{{__talos_clocked_[0-9_]+}}(
// CHECK: simulation.suspend.edge posedge
// CHECK: %[[OLD_SMALL:.*]] = simulation.ref.load %{{.*}}
// CHECK-NEXT: simulation.ref.store %[[OLD_SMALL]] to %{{.*}} {schedule.eval.nba_equivalent_store}
// CHECK: %[[SMALL:.*]] = simulation.ref.dyn_extract
// CHECK-SAME: !simulation.packed_array<16 : 0 x !simulation.logic<1>>
// CHECK-SAME: -> !simulation.ref<!simulation.packed_array<80 : 0 x !simulation.logic<1>>>
// CHECK-NEXT: simulation.nba.enqueue %{{.*}} to %[[SMALL]]
// CHECK: %[[OLD_WIDE:.*]] = simulation.ref.load %{{.*}}
// CHECK-NEXT: simulation.ref.store %[[OLD_WIDE]] to %{{.*}} {schedule.eval.nba_equivalent_store}
// CHECK: %[[WIDE:.*]] = simulation.ref.dyn_extract
// CHECK-SAME: !simulation.packed_array<128 : 0 x !simulation.logic<1>>
// CHECK-SAME: -> !simulation.ref<!simulation.packed_array<145 : 0 x !simulation.logic<1>>>
// CHECK-NEXT: simulation.nba.enqueue %{{.*}} to %[[WIDE]]
// CHECK: cf.br
//
// IMMEDIATE-LABEL: simulation.func private @{{__talos_fused_[0-9_]+}}.__talos_eval_body_0(
// IMMEDIATE-NOT: simulation.ref.store
// IMMEDIATE: %[[SMALL:.*]] = simulation.ref.dyn_extract
// IMMEDIATE-SAME: !simulation.packed_array<16 : 0 x !simulation.logic<1>>
// IMMEDIATE-SAME: -> !simulation.ref<!simulation.packed_array<80 : 0 x !simulation.logic<1>>>
// IMMEDIATE-NEXT: simulation.nba.enqueue %{{.*}} to %[[SMALL]]
// IMMEDIATE-NOT: simulation.ref.store
// IMMEDIATE: simulation.nba.enqueue
// IMMEDIATE-NOT: simulation.ref.store
// IMMEDIATE: %[[WIDE:.*]] = simulation.ref.dyn_extract
// IMMEDIATE-SAME: !simulation.packed_array<128 : 0 x !simulation.logic<1>>
// IMMEDIATE-SAME: -> !simulation.ref<!simulation.packed_array<145 : 0 x !simulation.logic<1>>>
// IMMEDIATE-NEXT: simulation.nba.enqueue %{{.*}} to %[[WIDE]]
// IMMEDIATE-NOT: simulation.ref.store
// IMMEDIATE: simulation.nba.enqueue
// IMMEDIATE-NOT: simulation.ref.store
// IMMEDIATE: simulation.return
//
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

module top;
  bit clk;
  logic signed [63:0] small_index, wide_index;
  logic [80:0] small_data;
  logic [145:0] wide_data;
  logic [16:0] q, old_q;
  logic [128:0] wide_q, old_wide_q;
  always #5 clk = !clk;
  always @(posedge clk) q[small_index +: 81] <= small_data;
  always @(posedge clk) old_q <= q;
  always @(posedge clk) wide_q[wide_index +: 146] <= wide_data;
  always @(posedge clk) old_wide_q <= wide_q;
  initial #7 $display("%h %h %h %h", q, old_q, wide_q, old_wide_q);
endmodule
