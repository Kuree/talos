// CLAUSE: clocking preponed vs zero
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  timeunit 1ns; timeprecision 1ps;
  bit clk=0; int data=0;
  always #5 clk=~clk;
  always @(posedge clk) data<=data+1;
  clocking cb @(posedge clk);
    input #1step old=data;
    input #0 updated=data;
  endclocking
  initial begin
    @(cb);
    if(cb.old!=0 || cb.updated!=1) $fatal(1,"first samples old=%0d updated=%0d",cb.old,cb.updated);
    @(cb);
    if(cb.old!=1 || cb.updated!=2) $fatal(1,"second samples old=%0d updated=%0d",cb.old,cb.updated);
    $display("PASS"); $finish;
  end
endmodule
