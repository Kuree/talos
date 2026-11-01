// CLAUSE: data_method = <string> syntax with the required des-cbc
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.11.1/keys.json %S/Inputs/34.5.11.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.11.1/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.11.2 and Table 34-3: des-cbc is required and aes128-cbc is a named option.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect end_protected
