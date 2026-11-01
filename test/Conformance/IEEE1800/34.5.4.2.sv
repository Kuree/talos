// CLAUSE: end_protected ends the pragmas of the block, and cleartext follows
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.4.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.4.2: the cleartext after end_protected instantiates a module only the payload defines.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=64),data_block
r9rBvoXoFXCmcX5/8vC3PIPWHLEqT51tVKSqlu6kNrMGTvHIZc9I9hNr4zeIRcErLYRcc1Y5Rr8w
EncL91GJmw==
`pragma protect end_protected
module top;int x;secret s(x);initial begin #1 $display("decrypted x=%0d",x);$finish;end endmodule
