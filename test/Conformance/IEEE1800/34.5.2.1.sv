// CLAUSE: end syntax closes a region
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: after end x=42
// 34.5.2.2 is ENCRYPTION INPUT and "DECRYPTION INPUT: none": both sides of end stay ordinary source.

`pragma protect begin
module helper(output int x);assign x=6*7;endmodule
`pragma protect end
module top;int x;helper h(x);initial begin #1 $display("after end x=%0d",x);$finish;end endmodule
