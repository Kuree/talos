// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/formats.sim
// RUN: %t/formats.sim
// RUN: FileCheck %s < %t/formats.vcd

// IEEE 1800-2023 21.7.2.2: vector values are written in binary without
// redundant leading characters: a leading 0 is implied, a leading x or z
// repeats, and a 0 before x or z stays (Tables 21-8, 21-9). Values up to 64
// bits are formatted from whole words, wider ones bit by bit; both agree.
module top;
  logic a1 = 0;
  logic [99:0] w = 0;
  logic [63:0] q = 0;
  logic [6:0] u = 0;
  logic [62:0] m = 0;
  logic [64:0] p = 0;
  bit [7:0] t = 0;
  int signed s = 0;
  initial begin
    $dumpfile("formats.vcd");
    $dumpvars(0, top);
    #1 w = (100'h1 << 96) | 100'h5;
    q = 64'h8000_0000_0000_0001;
    u = 7'b0x1z010;
    m = {1'bz, 62'h3};
    p = {1'b1, 64'h0};
    t = 8'h5;
    s = -2;
    #1 w = {100{1'bz}};
    q = {32'h0, 32'hffff_ffff};
    u = 7'b0001010;
    m = {63{1'bx}};
    p = 65'h1;
    t = 8'h80;
    s = 3;
    #1 $finish;
  end
endmodule

// CHECK-DAG: $var reg 1 [[A1:[^ ]+]] a1 $end
// CHECK-DAG: $var reg 100 [[W:[^ ]+]] w [99:0] $end
// CHECK-DAG: $var reg 64 [[Q:[^ ]+]] q [63:0] $end
// CHECK-DAG: $var reg 7 [[U:[^ ]+]] u [6:0] $end
// CHECK-DAG: $var reg 63 [[M:[^ ]+]] m [62:0] $end
// CHECK-DAG: $var reg 65 [[P:[^ ]+]] p [64:0] $end
// CHECK-DAG: $var {{[a-z]+}} 8 [[T:[^ ]+]] t [7:0] $end
// CHECK-DAG: $var {{[a-z]+}} 32 [[S:[^ ]+]] s [31:0] $end
// CHECK: $enddefinitions $end
// CHECK-NEXT: #0
// CHECK-NEXT: $dumpvars
// CHECK-DAG: 0[[A1]]
// CHECK-DAG: b0 [[W]]
// CHECK-DAG: b0 [[Q]]
// CHECK-DAG: b0 [[P]]
// CHECK: $end
// CHECK-NEXT: #1
// CHECK-DAG: b1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101 [[W]]
// CHECK-DAG: b1000000000000000000000000000000000000000000000000000000000000001 [[Q]]
// CHECK-DAG: b0x1z010 [[U]]
// CHECK-DAG: bz00000000000000000000000000000000000000000000000000000000000011 [[M]]
// CHECK-DAG: b10000000000000000000000000000000000000000000000000000000000000000 [[P]]
// CHECK-DAG: b101 [[T]]
// CHECK-DAG: b11111111111111111111111111111110 [[S]]
// CHECK: #2
// CHECK-DAG: bz [[W]]
// CHECK-DAG: b11111111111111111111111111111111 [[Q]]
// CHECK-DAG: b1010 [[U]]
// CHECK-DAG: bx [[M]]
// CHECK-DAG: b1 [[P]]
// CHECK-DAG: b10000000 [[T]]
// CHECK-DAG: b11 [[S]]
