// CLAUSE: encoding: base64 with line_length is reversed before decryption
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.9/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.9.2: "During decryption, the encoding directive is used to find the encoding algorithm used".

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=40,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbt
yJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIncwk0
z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4kt
yE00Xu84
`pragma protect end_protected
