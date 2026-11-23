// RUN: mkdir -p %t.dir
// RUN: talos -O3 --vpi=read %s -o %t.dir/sim
// RUN: cd %t.dir && ./sim && FileCheck %s < wave.vcd
// RUN: talos -O3 --two-state --vpi=read %s -o %t.dir/two
// RUN: cd %t.dir && ./two && FileCheck %s --check-prefix=TWO < wave.vcd
// TWO: $var reg 8 [[BITS:[^ ]+]] data [7:0] $end
// TWO: $var wire 8 [[BITS]] mirror [7:0] $end
// TWO: #3
// TWO: b10100 [[BITS]]
//
// The two continuous assignments tile the same source bits. Both names
// survive and the range emits one record, including transitions into X/Z.
// CHECK: $var reg 8 [[ID:[^ ]+]] data [7:0] $end
// CHECK: $var wire 8 [[ID]] mirror [7:0] $end
// CHECK: $var wire 8 [[SWAPPED:[^ ]+]] swapped [7:0] $end
// CHECK: #1
// CHECK-DAG: b11000011 [[ID]]
// CHECK-DAG: b111100 [[SWAPPED]]
// CHECK: #3
// CHECK-DAG: bx01z100 [[ID]]
// CHECK-DAG: bz100xx01 [[SWAPPED]]
module split_alias;
  logic [7:0] data;
  wire [7:0] mirror;
  assign mirror[7:4] = data[7:4];
  assign mirror[3:0] = data[3:0];
  wire [7:0] swapped;
  assign swapped[7:4] = data[3:0];
  assign swapped[3:0] = data[7:4];
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, split_alias);
    #1 data = 8'hc3;
    #2 data = 8'bxx01_z100;
    #1 $finish;
  end
endmodule
