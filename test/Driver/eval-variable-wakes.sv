// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t && %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

module top;
  bit seed, enable, a, b, c, d;
  always_comb a = d | seed;
  always_comb b = a;
  always_comb c = b;
  always_comb d = c & enable;

  logic [255:0] src = '0, disjoint, shared_wake;
  assign disjoint[127:0] = src[127:0];
  assign disjoint[255:128] = src[255:128];
  assign shared_wake[127:0] = src[127:0];
  assign shared_wake[255:128] = src[127:0];
  initial begin
    #1 enable = 1;
    seed = 1;
    src[1:0] = 2'b01;
    #1 seed = 0;
    #1 $display("held %b disjoint %b %b shared %b %b",
                {a,b,c,d}, disjoint[1:0], disjoint[129:128],
                shared_wake[1:0], shared_wake[129:128]);
    enable = 0;
    src[129:128] = 2'b1x;
    #1 $display("open %b disjoint %b %b shared %b %b",
                {a,b,c,d}, disjoint[1:0], disjoint[129:128],
                shared_wake[1:0], shared_wake[129:128]);
    $finish;
  end
endmodule
// CHECK: held 1111 disjoint 01 00 shared 01 01
// CHECK-NEXT: open 0000 disjoint 01 1x shared 01 01
