// CLAUSE: begin syntax opens a region whose source still simulates
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: region x=42
// 34.5.1.2 is ENCRYPTION INPUT and "DECRYPTION INPUT: none": without an encryption service the
// region must not be dropped or treated as ciphertext, so its design runs.

`pragma protect begin
module top;int x=6*7;initial begin $display("region x=%0d",x);$finish;end endmodule
`pragma protect end
