// CLAUSE: A clocking block samples inputs before and drives outputs after its event; blocking writes are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/14/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: clocking signal 'data' can only be written via a synchronous drive
// CHECK: 5 sampled=1 raw=2{{$}}
// CHECK-NEXT: 5 out=00{{$}}
// CHECK-NEXT: 15 sampled=2 out=44{{$}}

// Clause 14: the clocking event itself sees the pre-edge sample, and the drive lands one unit later.
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0;
  always #5 clk = ~clk;
  logic [7:0] in = 1, out = 0;
  default clocking cb @(posedge clk);
    default input #1step output #1;
    input in;
    output out;
  endclocking
  initial begin
    @(cb);                   // t=5
    in = 2;
    $display("%0t sampled=%0d raw=%0d", $time, cb.in, in);
    cb.out <= 8'h44;
    $display("%0t out=%h", $time, out);
    ##1;                     // t=15
    $display("%0t sampled=%0d out=%h", $time, cb.in, out);
    $finish;
  end
endmodule
