// CLAUSE: default queue min
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 7.4.5 / Table 7-1: queue slices, out-of-bounds reads give the element default (0 for int, x for 4-state), out-of-bounds writes are ignored.
// CHECK: slice 2: 2 3
// CHECK: oob q=0,0 ia=0 fa=xxxx w=xx
// CHECK: after size=4 ia=1,2,3

module top;
  int q[$] = '{1, 2, 3, 4};  int s[$];  int ia[3] = '{1, 2, 3};  logic [3:0] fa[2];
  logic [7:0] w = 8'hA5;  int i5 = 5, im = -1, k = 8;
  initial begin
    s = q[1:2];
    $display("slice %0d: %0d %0d", s.size(), s[0], s[1]);
    $display("oob q=%0d,%0d ia=%0d fa=%b w=%b", q[i5], q[im], ia[i5], fa[i5], w[k+:2]);
    q[10] = 99;  ia[i5] = 7;
    $display("after size=%0d ia=%0d,%0d,%0d", q.size(), ia[0], ia[1], ia[2]);
  end
endmodule
