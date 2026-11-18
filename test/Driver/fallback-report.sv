// RUN: talos -O3 --vpi=off --fallback-report=%t.jsonl %s -o %t
// RUN: FileCheck %s < %t.jsonl

// --fallback-report writes one plain JSON line per executor that leaves the
// tier-1 path. A fork without static multiplicity (IEEE 1800-2023 9.3.2) keeps its
// block in bytecode, so its process runs at a runtime checkpoint; the record
// names the process and the fork.
// CHECK: {"blocker":"{{.*}}fallback-report.sv:16:10","detail":"dynamic spawn multiplicity","kind":"checkpoint","loc":"{{.*}}fallback-report.sv:14:3","owner":"{{unit_[0-9]+}}","reason":"runtime-checkpoint-actor"}
module fallback_report;
  logic clk = 0;
  logic [7:0] count = 0;
  logic [7:0] forked = 0;
  always #5 clk = ~clk;
  always @(posedge clk) begin
    count <= count + 1;
    fork forked <= forked + 1; join_none
  end
  initial #48 $finish;
endmodule
