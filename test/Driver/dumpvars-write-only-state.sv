// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O1 %s -o sim && ./sim > /dev/null
// RUN: FileCheck %s < %t/write-only.vcd

// IEEE 1800-2023 21.7: a VCD file records the values of the selected variables. A
// variable nothing in the design reads still has them, so optimization cannot
// remove its stores when a dump selects it.
module top;
  reg [3:0] initialized = 4'b10x1;
  reg [3:0] written;
  initial begin
    $dumpfile("write-only.vcd");
    $dumpvars;
    written = 5;
    #1 written = 6;
    #1 $finish;
  end
endmodule

// CHECK: #0
// CHECK-DAG: b10x1 !
// CHECK-DAG: b101 "
// CHECK: #1
// CHECK: b110 "
