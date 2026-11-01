// CLAUSE: Assertion semantics
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  bit clk=0; bit value=0; int passes=0;
  always #5 clk=~clk;
  always @(posedge clk) value<=1;
  p: assert property (@(posedge clk) value==0) passes++;
  initial begin #6; if(passes!=1) $fatal(1,"Preponed sample lost passes=%0d",passes); $display("PASS"); $finish; end
endmodule
