// CLAUSE: protect data_decrypt_key parser availability
// XFAIL: *
// Protected payload processing is unavailable; no decryption key-registration interface is assumed.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

`pragma protect encoding=(enctype="base64",bytes=8)
`pragma protect data_decrypt_key
AAAAAAAAAAA=
module top;endmodule
