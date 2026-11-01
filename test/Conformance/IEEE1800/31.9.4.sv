// CLAUSE: Without the negative timing check option, delayed signals copy the originals
// XFAIL: *
// No invocation option turns negative timing checks off, and explicit delayed signals are not executable; --no-negative-timing-checks is the spelling this probe expects.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --no-negative-timing-checks -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: dc=1 dd=0 q=0{{$}}
// CHECK-NEXT: dc=1 dd=1 q=0{{$}}

// 31.9.4: run without the option, delayed_reference and delayed_data become
// copies of the original signals, with no added delay.
module cell_t(input wire c, d, output logic q = 0);
  timeunit 1ns; timeprecision 1ps;
  wire dc, dd;
  always @(posedge dc) q <= dd;
  specify
    $setuphold(posedge c, d, -2, 5, , , , dc, dd);
  endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ps;
  logic c = 0, d = 0;
  wire q;
  cell_t dut(c, d, q);
  initial begin
    #10 c = 1;
    #0.1 $display("dc=%b dd=%b q=%b", dut.dc, dut.dd, q);
    d = 1;
    #0.1 $display("dc=%b dd=%b q=%b", dut.dc, dut.dd, q);
    $finish;
  end
endmodule
