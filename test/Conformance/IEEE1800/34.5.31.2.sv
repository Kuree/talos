// CLAUSE: Following reset, all protect pragma keywords are restored to their default values
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.31.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.31.2: the data_keyname before reset is gone. If it survived, the stale key would decrypt garbage.

`pragma protect data_keyname="stale"
`pragma protect reset
`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect end_protected
