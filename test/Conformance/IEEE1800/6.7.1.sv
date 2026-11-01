// CLAUSE: Net declarations set type, width, default value and delay; net type followed by reg is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.7.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: net type keyword cannot be followed by the 'reg' keyword
// CHECK: defaults z zzzzzzzzzzzzzzzz x{{$}}
// CHECK-NEXT: bits 1 16 32 9{{$}}
// CHECK-NEXT: member 1 a5{{$}}
// CHECK-NEXT: before delay 1{{$}}
// CHECK-NEXT: after delay 0{{$}}

// 6.7.1: nets default to z and trireg to x, the implicit type is logic, and #3 shows on the net.
module top;
  timeunit 1ns; timeprecision 1ns;
  typedef logic [31:0] addressT;
  wire w;
  wire [15:0] ww;
  wire addressT w1;
  wire struct packed {logic ecc; logic [7:0] data;} memsig;
  trireg (large) logic #(0,0,0) cap1;
  logic src = 1;
  wire #3 delayed;
  assign delayed = src;
  assign memsig = 9'h1a5;
  initial begin
    $display("defaults %b %b %b", w, ww, cap1);
    $display("bits %0d %0d %0d %0d", $bits(w), $bits(ww), $bits(w1), $bits(memsig));
    #5 $display("member %b %h", memsig.ecc, memsig.data);
    src = 0;
    #2 $display("before delay %b", delayed);
    #2 $display("after delay %b", delayed);
    $finish;
  end
endmodule
