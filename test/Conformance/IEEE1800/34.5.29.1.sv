// CLAUSE: runtime_license = (library, entry, feature, exit, match) syntax
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %clang -shared -fPIC %S/Inputs/34.5.29.1/license.c -o %t.license.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.29.1/keys.json %s -o %t.exe
// RUN: %t.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.29.1/keys.json %S/Inputs/34.5.29.1/denied.sv -o %t.denied.exe
// RUN: %not %t.denied.exe
// CHECK: license feature=licensed
// CHECK: decrypted x=42
// CHECK: license released
// CHECK: license feature=denied
// CHECK-NOT: decrypted
// CHECK: {{[^0-9]13[^0-9]}}
// 34.5.29.2: "execution shall not begin, and the application shall produce an error message that includes the
// return value". The denied design compiles, and fails only when it is run.

`pragma protect begin_protected
`pragma protect runtime_license=(library="./probe.license.so",entry="check",feature="licensed",exit="release",match=42)
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect end_protected
