// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 7.2.1, 10.4.2, 11.5.1: a partial NBA to a packed member
// clips to that member, preserving adjacent struct fields. Retain its bounded
// NBA instead of flattening it to a root-relative blocking store. Whole-root
// dynamic writes and fixed member stores remain fusion controls.
// CHECK-LABEL: simulation.func private @{{__talos_clocked_[0-9_]+}}(
// CHECK: %[[FIELD:.*]] = simulation.ref.subelement {{.*}} -> !simulation.ref<!simulation.packed_array<126 : 0 x !simulation.logic<1>>>
// CHECK: %[[PART:.*]] = simulation.ref.dyn_extract %[[FIELD]] from
// CHECK-NEXT: simulation.nba.enqueue %{{.*}} to %[[PART]]
// CHECK-DAG: %[[FLAT:.*]] = simulation.ref.dyn_extract {{.*}} : (!simulation.ref<!simulation.packed_array<63 : 0 x !simulation.logic<1>>>
// CHECK-DAG: simulation.ref.store %{{.*}} to %[[FLAT]] {schedule.eval.nba_equivalent_store}
// CHECK-DAG: simulation.ref.store %{{.*}} to %{{.*}} {schedule.eval.nba_equivalent_store} : !simulation.packed_array<15 : 0 x !simulation.logic<1>>
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

module top;
  typedef struct packed {logic [2:0] hi; logic [126:0] data; logic [4:0] lo;} packet_t;
  typedef struct packed {logic [15:0] data; logic [2:0] guard_bits;} fixed_t;
  bit clk;
  logic signed [63:0] idx;
  logic [15:0] d;
  packet_t q;
  fixed_t fixed_q;
  logic [63:0] flat;
  logic [134:0] old_q;
  always #5 clk = !clk;
  always @(posedge clk) q.data[idx +: 8] <= d[7:0];
  always @(posedge clk) old_q <= q;
  always @(posedge clk) flat[idx +: 8] <= d[7:0];
  always @(posedge clk) fixed_q.data <= d;
  initial #7 $display("%b %b %b %b", q, old_q, flat, fixed_q);
endmodule
