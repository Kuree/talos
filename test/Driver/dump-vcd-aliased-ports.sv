// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/s3.sim
// RUN: %t/s3.sim
// RUN: FileCheck %s < %t/s3.vcd

// IEEE 1800-2023 23.3.3, 21.7: variable port connections are implied
// continuous assignments. The compiler shares the storage of an input port and
// its source (u.d and q) and of an output port and its sink (u.data_o and r)
// while dumping too; each eliminated name keeps its declaration and reads the
// surviving root's bits, so it shares that root's identifier code.
module leaf(input logic clk, input logic [3:0] d, output logic [3:0] data_o);
  always_ff @(posedge clk) data_o <= d;
endmodule
module top;
  logic clk = 0;
  logic [3:0] q = 0;
  logic [3:0] r;
  leaf u(.clk(clk), .d(q), .data_o(r));
  always #5 clk = ~clk;
  always_ff @(posedge clk) q <= q + 1;
  initial begin
    $dumpfile("s3.vcd");
    $dumpvars(0, top);
    #32 $finish;
  end
endmodule

// CHECK: $scope module top $end
// CHECK-NEXT: $scope module u $end
// CHECK-NEXT: $var reg 1 ! clk $end
// CHECK-NEXT: $var reg 4 " d [3:0] $end
// CHECK-NEXT: $var reg 4 # data_o [3:0] $end
// CHECK-NEXT: $upscope $end
// CHECK-NEXT: $var reg 1 $ clk $end
// CHECK-NEXT: $var reg 4 " q [3:0] $end
// CHECK-NEXT: $var reg 4 # r [3:0] $end
// CHECK-NEXT: $upscope $end
// CHECK-NEXT: $enddefinitions $end
// CHECK-NEXT: #0
// CHECK-NEXT: $dumpvars
// CHECK-NEXT: 0$
// CHECK-NEXT: b0 "
// CHECK-NEXT: 0!
// CHECK-NEXT: bx #
// CHECK-NEXT: $end
// CHECK-NEXT: #5
// CHECK-NEXT: 1$
// CHECK-NEXT: b1 "
// CHECK-NEXT: 1!
// CHECK-NEXT: b0 #
// CHECK-NEXT: #10
// CHECK-NEXT: 0$
// CHECK-NEXT: 0!
// CHECK-NEXT: #15
// CHECK-NEXT: 1$
// CHECK-NEXT: b10 "
// CHECK-NEXT: 1!
// CHECK-NEXT: b1 #
// CHECK-NEXT: #20
// CHECK-NEXT: 0$
// CHECK-NEXT: 0!
// CHECK-NEXT: #25
// CHECK-NEXT: 1$
// CHECK-NEXT: b11 "
// CHECK-NEXT: 1!
// CHECK-NEXT: b10 #
// CHECK-NEXT: #30
// CHECK-NEXT: 0$
// CHECK-NEXT: 0!
// CHECK-NOT: {{.}}
