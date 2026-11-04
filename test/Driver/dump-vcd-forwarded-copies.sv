// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/f.sim
// RUN: %t/f.sim
// RUN: FileCheck %s < %t/f.vcd

// IEEE 1800-2023 21.7: several names may share one identifier code when they
// always hold the same value. A continuous copy of one whole source range is
// forwarded into its readers while dumping too, and its name reads the
// source's bits at every slot end: w, w2 (a copy of the copy), the port copies
// s.i and s.o, and p share q's code; hi reads bits [3:2] of q under its own
// code. The expression net nq keeps its own process and code.
module sub(input logic [3:0] i, output logic [3:0] o);
  assign o = i;
endmodule
module top;
  logic clk = 0;
  logic [3:0] q = 0;
  wire [3:0] w = q;
  wire [3:0] w2 = w;
  wire [3:0] nq = ~q;
  wire [1:0] hi = q[3:2];
  wire [3:0] p;
  sub s(.i(q), .o(p));
  always #5 clk = ~clk;
  always_ff @(posedge clk) q <= q + 1;
  initial begin
    $dumpfile("f.vcd");
    $dumpvars(0, top);
    #22 $finish;
  end
endmodule

// CHECK: $scope module top $end
// CHECK-NEXT: $scope module s $end
// CHECK-NEXT: $var reg 4 ! i [3:0] $end
// CHECK-NEXT: $var reg 4 ! o [3:0] $end
// CHECK-NEXT: $upscope $end
// CHECK-NEXT: $var reg 1 " clk $end
// CHECK-NEXT: $var wire 2 # hi [1:0] $end
// CHECK-NEXT: $var wire 4 $ nq [3:0] $end
// CHECK-NEXT: $var wire 4 ! p [3:0] $end
// CHECK-NEXT: $var reg 4 ! q [3:0] $end
// CHECK-NEXT: $var wire 4 ! w [3:0] $end
// CHECK-NEXT: $var wire 4 ! w2 [3:0] $end
// CHECK-NEXT: $upscope $end
// CHECK-NEXT: $enddefinitions $end
// CHECK-NEXT: #0
// CHECK-NEXT: $dumpvars
// CHECK-NEXT: 0"
// CHECK-NEXT: b0 !
// CHECK-NEXT: b0 #
// CHECK-NEXT: b1111 $
// CHECK-NEXT: $end
// CHECK-NEXT: #5
// CHECK-NEXT: 1"
// CHECK-NEXT: b1 !
// CHECK-NEXT: b1110 $
// CHECK-NEXT: #10
// CHECK-NEXT: 0"
// CHECK-NEXT: #15
// CHECK-NEXT: 1"
// CHECK-NEXT: b10 !
// CHECK-NEXT: b1101 $
// CHECK-NEXT: #20
// CHECK-NEXT: 0"
// CHECK-NOT: {{.}}
