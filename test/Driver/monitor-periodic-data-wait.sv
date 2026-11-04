// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.err
// RUN: FileCheck %s < %t.out
// RUN: FileCheck %s --check-prefix=DIAG < %t.err

// IEEE 1800-2023 4.4.2.9, 21.2.3: the testbench waits on dout, which the
// $monitor also compares; the monitor holds no subscription to it, so its
// writes wake only the testbench. The runtime compares the arguments at the
// end of every slot of the generated periodic loop and reports once per slot
// in which an argument changed, whether the loop's clocked writes or the
// testbench changed it. (An observer keeps the loop off the runtime's shared
// calendar.) The text is what every other tier prints.
module dut(input logic clk, input logic [7:0] din, output logic [7:0] dout);
  logic [7:0] acc = 0;
  always_ff @(posedge clk) acc <= acc + din;
  assign dout = acc;
endmodule

module top;
  logic clk = 0;
  logic [7:0] din = 1, dout;
  always #5 clk = ~clk;
  dut d(.clk(clk), .din(din), .dout(dout));
  initial begin
    $monitor("t=%0t din=%0d dout=%0d", $time, din, dout[7:1]);
    #1 repeat (3) begin @(dout); din <= din + 8'd3; end
    #15 din = 8'd2;
    #20 $finish;
  end
endmodule

// CHECK: t=0 din=1 dout=0
// CHECK-NEXT: t=5 din=4 dout=0
// CHECK-NEXT: t=15 din=7 dout=2
// CHECK-NEXT: t=25 din=10 dout=6
// CHECK-NEXT: t=35 din=10 dout=11
// CHECK-NEXT: t=40 din=2 dout=11
// CHECK-NEXT: t=45 din=2 dout=12
// CHECK-NEXT: t=55 din=2 dout=13
// CHECK-NOT: t=

// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations={{[1-9]}}
