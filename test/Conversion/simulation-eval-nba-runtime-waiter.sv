// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto' -o %t.mlir
// RUN: FileCheck %s < %t.mlir

// An NBA update is an update event for every waiter on the root (IEEE
// 1800-2023 4.5, 10.4.2, 9.4.2). The initial repeat loop stays a runtime-owned
// finite bootstrap, so its wait on `count` has no generated ready bit. The
// generated NBA barrier hands its exact edge wake to the runtime, tagged as a
// runtime-routed publication for the eval call-closure verifier.
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK: llvm.call @talos_rt_v1_scheduler_activate_static_nodes({{.*}}) {schedule.eval.runtime_routed_publication}

module eval_nba_runtime_waiter;
  logic clk = 0;
  logic rst_n = 0;
  int count = 0;
  logic hit = 0;
  initial forever #5 clk = ~clk;
  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1;
  end
  always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0;
    else count <= count + 1;
  initial begin
    #100;
    repeat (2) @(posedge count[0]);
    hit = 1;
  end
  initial #300 $finish;
endmodule
