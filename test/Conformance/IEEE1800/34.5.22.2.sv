// CLAUSE: protect digest_block parser availability
// XFAIL: *
// Protected payload processing is unavailable; no decryption key-registration interface is assumed.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect digest_method="md5"
`pragma protect digest_key_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=56)
`pragma protect data_block
EjRWeJCrze9/6icnxeWP25OLQhsO6GdiMuh4T3IeBmaUSxH/quPr0NWIniXcRWrCnDnGlpp7HcE=
`pragma protect encoding=(enctype="base64",line_length=76,bytes=24),digest_block
/ty6CYdlQyEb10evN7wbsgkHYnzYX1lJ
`pragma protect end_protected
