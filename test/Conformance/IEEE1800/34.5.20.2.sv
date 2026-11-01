// CLAUSE: The tool decrypts the key_block to find digest_decrypt_key and digest_key_method
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.20.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.20.2: only the session key in the key_block decrypts the digest.

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect digest_method="md5"
`pragma protect key_keyowner="lrm-audit"
`pragma protect key_keyname="test-key"
`pragma protect key_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=144),key_block
YpS0Dkt9zdvW8aEQJpyr4rQSmC6zeRU1ZgrnfCw3KH6xwyJTH8S/wI9y+kA8lRaZ7OY74EaL4OqM
LoG7tou2JELXfLqieyGHtOGpg6bersgfPeVwRGlKzRq7F9iMx+3w0bjvC2WvJ4XPyPtWQu+JGA8t
MB9I4vtuZc2M3fFY+BAbGIsvYMlPukKy8gRpXyh9
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect encoding=(enctype="base64",line_length=76,bytes=32),digest_block
xWYU19yV9VoVJCCzQ67XqZNbZhX3YhojPNaenGzvNgo=
`pragma protect end_protected
