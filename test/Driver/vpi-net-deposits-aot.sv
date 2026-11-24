// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi-net-deposits-aot.c -I%resource_dir/include -o %t.plugin.so
// RUN: talos -O3 --vpi=full --native-scheduler=aot %s %t.plugin.so -o %t.sim
// RUN: %t.sim | FileCheck %s --match-full-lines

// IEEE 1800-2023 38.34 under the generated AOT schedule, which a design that
// calls DPI does not reach. The plugin puts on two continuously driven nets
// at time 11: a flop samples the held put on its next edge, a driver that
// changes takes w back (17), and a driver re-evaluated to its old value
// (r & 0f stays 01) leaves the put on masked.
module top;
  bit clock = 0;
  logic [7:0] r = 8'h11;
  wire [7:0] w = r;
  wire [7:0] masked = r & 8'h0f;
  logic [7:0] q;
  always @(posedge clock) q <= w;
  initial repeat (3) begin
    #5 clock = 1;
    #5 clock = 0;
  end
  initial begin
    #12 $display("put: w=%h masked=%h q=%h", w, masked, q);
    #4 $display("edge: w=%h masked=%h q=%h", w, masked, q);
    #1 r = 8'h31;
    #1 $display("driver changed: w=%h masked=%h q=%h", w, masked, q);
    #8 $display("edge: w=%h masked=%h q=%h", w, masked, q);
    $finish;
  end
endmodule

// CHECK: put: w=aa masked=55 q=11
// CHECK-NEXT: edge: w=aa masked=55 q=aa
// CHECK-NEXT: driver changed: w=31 masked=55 q=aa
// CHECK-NEXT: edge: w=31 masked=55 q=31
