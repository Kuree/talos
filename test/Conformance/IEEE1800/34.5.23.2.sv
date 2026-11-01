// CLAUSE: Key-block decryption uses key_keyowner: selects the key_block's key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.23.2/keys.json %S/Inputs/34.5.23.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.23.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.27.2: the key_block is decrypted with this key, and its text gives the data key.

`pragma protect begin_protected
`pragma protect key_keyowner="lrm-audit"
`pragma protect key_keyname="test-key"
`pragma protect key_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=136),key_block
krwUJ8Shh3n09R3boKYn7neHjfnDQjJdiW+rOuSGnR7tomwj5xP6ozX02XW027pLO8tzmM1oa/Da
4qIo+ojC/sugimObiT9YvH+yp78qFCMYYEGy44qF8gyGX+lZ9PEM1U6jsF5Nu4Gg/BwL0UkC1b3Q
Wb4G7gSVax/TVQlYZVa7xvjMMvd+1Q==
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbc49zCO5k/jJ7bS+kh255+Hr/n0qfKxR0SG9l22EuSiCOnbYK+vv6xHT3AQCfPN/i0
Jy5ZBHzaSk09DhnXVKa1qa8F7emKls9prd9diQUh2C/UfA25aLuz
`pragma protect end_protected
