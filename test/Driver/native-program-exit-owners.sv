// RUN: talos -O3 --native-scheduler=eval --mlir-timing %s -o %t.eval 2> %t.timing
// RUN: FileCheck %s --check-prefix=PLAN < %t.timing
// RUN: talos -O0 --native-scheduler=generic %s -o %t.generic
// RUN: %t.eval > %t.eval.out
// RUN: %t.generic > %t.generic.out
// RUN: diff -u %t.generic.out %t.eval.out
// RUN: FileCheck %s < %t.eval.out

// $exit kills every process of its program (IEEE 1800-2023 24.7), so the
// program's processes are runtime-owned, including one that never calls
// $exit. The $monitor evaluator (21.2.3) its initial procedure spawns is
// runtime-owned as well: it waits on observers of its arguments. The DUT flop
// keeps its generated owner (two-tier P1e).
module dut(input logic clk, output logic [7:0] count = 0);
  always_ff @(posedge clk) count <= count + 1;
endmodule

program automatic tb(input logic clk, input logic [7:0] count);
  int seen = 0;
  initial begin
    $monitor("monitor seen=%0d", seen);
    repeat (3) @(posedge clk);
    $display("tb count=%0d seen=%0d", count, seen);
    $exit;
  end
  initial forever @(posedge clk) seen++;
endprogram

module native_program_exit_owners;
  logic clk = 0;
  logic [7:0] count;
  always #5 clk = ~clk;
  dut d(.clk, .count);
  tb t(.clk, .count);
  final $display("final t=%0t count=%0d", $time, count);
endmodule

// PLAN-DAG: withheld actor: {{.*}}.sv":20:3) reason=program exit is runtime-owned
// PLAN-DAG: withheld actor: {{.*}}.sv":21:5) reason=computed or conditional wait
// PLAN-DAG: withheld actor: {{.*}}.sv":26:3) reason=program exit is runtime-owned
// PLAN: talos eval executor inventory: tier1=2 tier2=0
// PLAN: talos started owners: admitted=1
// CHECK: monitor seen=0
// CHECK-NEXT: monitor seen=1
// CHECK-NEXT: monitor seen=2
// CHECK-NEXT: tb count=3 seen=2
// CHECK-NEXT: final t=25 count=3
