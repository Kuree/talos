// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// A Verilog-2001 combinational block waits for its first event before it
// runs (IEEE 1800-2023 9.4.2), unlike always_comb (9.2.2.2.2): its outputs
// stay X until then. A glitch that returns an input to its old value is still
// an event, so the block runs once; a write of an unchanged value is not.
module native_armed_event_combinational;
  logic [3:0] a = 0, b = 0;
  logic [3:0] y, w;
  always @(a or b) begin
    y = a + b;
    w = y ^ 4'hf;
  end
  initial begin
    #1 $display("t1 y=%b w=%b", y, w);
    a = 4'd1;
    a = 4'd0;
    #1 $display("t2 y=%b w=%b", y, w);
    a = 4'd2;
    #1 $display("t3 y=%0d w=%0d", y, w);
    b = 4'd0;
    #1 $display("t4 y=%0d w=%0d", y, w);
    b = 4'd5;
    #1 $display("t5 y=%0d w=%0d", y, w);
    $finish;
  end
endmodule

// CHECK: t1 y=xxxx w=xxxx
// CHECK-NEXT: t2 y=0000 w=1111
// CHECK-NEXT: t3 y=2 w=13
// CHECK-NEXT: t4 y=2 w=13
// CHECK-NEXT: t5 y=7 w=8
