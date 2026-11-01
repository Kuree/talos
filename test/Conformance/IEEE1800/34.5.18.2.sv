// CLAUSE: Digest verification uses digest_keyname: selects the digest's key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.18.2/keys.json %S/Inputs/34.5.18.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.18.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.22.2: the digest_block is decrypted with this key, then compared with the payload's digest.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect digest_keyowner="lrm-audit"
`pragma protect digest_keyname="test-key"
`pragma protect digest_key_method="des-cbc"
`pragma protect digest_method="md5"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect encoding=(enctype="base64",line_length=76,bytes=32),digest_block
xWYU19yV9Vr+qIXn7wr2k7CiZthph4dvG0eAGKDR5i8=
`pragma protect end_protected
