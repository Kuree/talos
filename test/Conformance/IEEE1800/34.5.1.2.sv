// CLAUSE: Nesting of pragma begin-end blocks shall be an error
// XFAIL: *
// Nested begin-end is only a warning (-Wnested-protect-begin), though 34.5.1.2 says it "shall be an error".
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/34.5.1.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: nested pragma protect begin
// CHECK: region x=42
// 34.5.1.2 is ENCRYPTION INPUT and "DECRYPTION INPUT: none": without an encryption service the
// region must not be dropped or treated as ciphertext, so its design runs.
// The illegal source nests one begin inside another.

`pragma protect begin
module top;int x=6*7;initial begin $display("region x=%0d",x);$finish;end endmodule
`pragma protect end
