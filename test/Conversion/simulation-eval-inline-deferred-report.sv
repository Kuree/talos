// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval' | FileCheck %s --implicit-check-not=__talos_path_known --implicit-check-not=__talos_checkpoint_path
// RUN: talos -emit-slang -DPROBE %s | talos-opt --test-talos-native-backend='scheduler=eval' | FileCheck %s --check-prefix=PROBE

// IEEE 1800-2023 12.5.3.1 and 12.4.2.1: a unique-case violation is detected
// when the statement executes, but its report waits on the process's queue
// until the Observed region, and a flush point (here, the next evaluation of
// the always_comb) discards it. A deferred assertion queues its action call
// the same way, with the current values of its arguments (16.4.1). Each report
// carries the compiler-maintained flush epoch (16.4.2), so queuing its ticket
// and starting its Observed-region evaluator need no runtime process. Both stay
// inline in the generated activation and in its two-state copy: the body is no
// checkpoint route, and no path probe dry-runs it before every activation.
module m;
  logic clk = 0;
  logic [7:0] n = 0;
  logic [1:0] sel;
  logic [7:0] y, q;
  string tag = "t";
  always #5 clk = ~clk;
  always_ff @(posedge clk) n <= n + 1;
  assign sel = n[1:0];
  always_comb begin
    y = 0;
    unique casez (sel)
      2'b00: y = 10;
      2'b01: y = 20;
      2'b1?: y = 30;
      2'b11: y = 40;
    endcase
`ifdef PROBE
    a: assert #0 (n != 8'd7) else $error("%s", tag);
`else
    a: assert #0 (n != 8'd7) else $error("n=%0d", n);
`endif
  end
  always_ff @(posedge clk) q <= y;
endmodule

// CHECK-LABEL: llvm.func @unit_6.__talos_eval_body_0(
// CHECK: %[[ASSERTION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue_for_assertion({{.*}}) {schedule.eval.direct_output}
// CHECK: llvm.call @unit_6.fork.{{[0-9.]+}}.__talos_spawn(%arg0, {{.*}}%[[ASSERTION]], %{{[0-9]+}}) {schedule.eval.direct_output}
// CHECK: %[[VIOLATION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue({{.*}}) {schedule.eval.direct_output}
// CHECK: llvm.call @unit_6.violation.{{[0-9.]+}}.__talos_spawn(%arg0, %[[VIOLATION]], %{{[0-9]+}}) {schedule.eval.direct_output}

// CHECK-LABEL: llvm.func @unit_6.__talos_eval_body_0.__talos_two_state_0(
// CHECK: %[[ASSERTION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue_for_assertion({{.*}}) {schedule.eval.direct_output}
// CHECK: llvm.call @unit_6.fork.{{[0-9.]+}}.__talos_spawn(%arg0, {{.*}}%[[ASSERTION]], %{{[0-9]+}}) {schedule.eval.direct_output}
// CHECK: %[[VIOLATION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue({{.*}}) {schedule.eval.direct_output}
// CHECK: llvm.call @unit_6.violation.{{[0-9.]+}}.__talos_spawn(%arg0, %[[VIOLATION]], %{{[0-9]+}}) {schedule.eval.direct_output}

// A string argument is a managed handle the report's evaluator retains, which
// needs the actor's collector roots: that report keeps its runtime checkpoint
// and the owner keeps its path probe. The probe skips the inline violation
// report (it executes no report), and only the checkpoint callback queues the
// assertion's report.
// PROBE-LABEL: llvm.func @unit_6.__talos_eval_body_0(
// PROBE-NOT: deferred_enqueue_for_assertion
// PROBE: %[[VIOLATION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue({{.*}}) {schedule.eval.direct_output}
// PROBE: llvm.call @unit_6.violation.{{[0-9.]+}}.__talos_spawn(%arg0, %[[VIOLATION]], %{{[0-9]+}}) {schedule.eval.direct_output}

// PROBE-LABEL: llvm.func @unit_6.__talos_eval_body_0.__talos_two_state_0(
// PROBE-NOT: deferred_enqueue_for_assertion
// PROBE: %[[VIOLATION:[0-9]+]] = llvm.call @talos_rt_v1_deferred_enqueue({{.*}}) {schedule.eval.direct_output}
// PROBE: llvm.call @unit_6.violation.{{[0-9.]+}}.__talos_spawn(%arg0, %[[VIOLATION]], %{{[0-9]+}}) {schedule.eval.direct_output}

// PROBE-LABEL: llvm.func @unit_6.__talos_eval_body_0.__talos_path_known_0(
// PROBE-NOT: deferred_enqueue
// PROBE-NOT: __talos_spawn
// PROBE-LABEL: llvm.func @unit_6.__talos_eval_body_0.__talos_checkpoint_path_0(

// PROBE-LABEL: llvm.func @__talos_eval_checkpoint_body_v1_{{[0-9]+}}(
// PROBE: llvm.call @talos_rt_v1_deferred_enqueue_for_assertion({{[^)]*}}) : (
// PROBE: llvm.call @unit_6.fork.{{[0-9.]+}}.__talos_spawn({{[^)]*}}) : (
