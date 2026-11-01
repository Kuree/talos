// CLAUSE: The data_method specifies the algorithm used to decrypt the data_block
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.11.2/keys.json %S/Inputs/34.5.11.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.11.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.11.2 and Table 34-3: des-cbc is required and aes128-cbc is a named option.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=112),data_block
16xOf2gocWZW/w1BuKc+j2NU6mtBUNkAm3CjJOimgrkX/lX89K94ubwdkxJhErbIJEeQp1aHbdGf
5Wx37FoyM5tHKSZAR6ImC4xoar0oCUXQ4B4/Kfhlkt3W17VVK1TiA88wRTQ2QtUgNcfK5rxFfg==
`pragma protect end_protected
