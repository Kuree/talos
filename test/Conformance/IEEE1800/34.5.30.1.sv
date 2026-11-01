// CLAUSE: comment = <string> syntax within a decrypted envelope
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.30.1/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.30.2: comment is enclosed in the envelope but is not part of decryption.

`pragma protect begin_protected
`pragma protect comment="Copyright Acme", data_keyowner="lrm-audit", data_keyname="test-key", data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect end_protected
