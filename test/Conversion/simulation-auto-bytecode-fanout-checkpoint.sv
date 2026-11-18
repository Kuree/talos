// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto timing=true fallback-report=true' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --check-prefix=FALLBACK < %t.trace
// RUN: FileCheck %s < %t.mlir

// The clocked process forks a new process on each edge (IEEE 1800-2023 9.3.2
// join_none); a spawn without static multiplicity keeps its block in
// bytecode. Only that process goes to the lower tier: every activation
// reaches the generic scheduler at a runtime checkpoint, and the rest of the
// design keeps Auto's generated eval island.
// The fallback report names each demoted executor and its cause: the forking
// block is a checkpoint because of its fork, and each generate stage's
// continuous assignment reactivates itself through mix (tier 2).
// FALLBACK: talos fallback: {"blocker":"{{.*}}.sv:36:10","detail":"dynamic spawn multiplicity","kind":"checkpoint","loc":"{{.*}}.sv:33:3","owner":"{{unit_[0-9]+}}","reason":"runtime-checkpoint-actor"}
// FALLBACK-COUNT-2: talos fallback: {"detail":"edge={{[0-9]+}}->{{[0-9]+}} watch={{[0-9]+}}","kind":"tier2","loc":"{{.*}}.sv:31:12","owner":"{{unit_[0-9]+}}.__talos_eval_body_0","reason":"local-feedback"}
// FALLBACK-NOT: talos fallback:
// TRACE-NOT: partial eval disabled
// TRACE: talos eval executor inventory: tier1=1 tier2=2 runtime_checkpoints=1
// TRACE-NOT: partial eval disabled
// CHECK: llvm.func @__talos_eval_dispatch_v1

module native_partial_auto_fallback_bytecode_fanout;
  logic clk = 0;
  logic en = 1;
  logic [7:0] b = 0;
  logic [31:0] wide = 0;
  logic [31:0] mix [0:2];
  always #5 clk = ~clk;
  assign mix[0] = wide;
  for (genvar g = 0; g < 2; g++) begin : heavy
    assign mix[g + 1] = (mix[g] << 1) ^ (mix[g] >> 3) ^ (32'h9e3779b9 + g);
  end
  always @(posedge clk) begin
    b <= 8'd1;
    if (en) b <= 8'd0;
    fork wide[15:8] <= wide[15:8] + 1; join_none
    wide[31:24] <= wide[31:24] + 1;
  end
  initial begin
    automatic string label = "done";
    #48 $display("%s b=%0d n=%0d mix=%h", label, b, wide[31:24], mix[2]);
    $finish;
  end
endmodule
