// CLAUSE: A denied decrypt_license stops decryption with the entry's return value in the error
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %clang -shared -fPIC %S/Inputs/34.5.28.2/license.c -o %t.license.so
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.28.2/keys.json %S/Inputs/34.5.28.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.28.2/keys.json %s -o %t.exe
// RUN: %t.exe
// DIAG: license feature=denied
// DIAG: {{[^0-9]13[^0-9]}}
// DIAG: license feature=licensed
// DIAG: license released
// CHECK: decrypted x=42
// 34.5.28.2: entry receives the feature, its result is compared with match, the error includes a nonmatching
// result, and exit runs before the decrypting application exits.

`pragma protect begin_protected
`pragma protect decrypt_license=(library="./probe.license.so",entry="check",feature="licensed",exit="release",match=42)
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect end_protected
