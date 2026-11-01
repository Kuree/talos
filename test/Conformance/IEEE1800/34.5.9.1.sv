// CLAUSE: encoding = (enctype, line_length, bytes) syntax, with the required uuencode
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.9.1/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// Table 34-2: uuencode is one of the two required enctype values.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="uuencode",bytes=96),data_block
MUZQ.?V@H<6;K@K/?[R--V^<=7FNMJ*COZ[D[(7;MR)/A1C]CP21N_XT+C\51
M515B*KY;(J]E/8(G<PDTSW=AMM-<PZ-+<37+4?>(YB1=B !U3"]MKO1/.XDM
&R$TT7N\X
`pragma protect end_protected
