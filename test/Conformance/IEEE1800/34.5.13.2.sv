// CLAUSE: protect data_public_key parser availability
// XFAIL: *
// Protected payload processing is unavailable; no decryption key-registration interface is assumed.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

`pragma protect encoding=(enctype="base64",bytes=162)
`pragma protect data_public_key
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC/jY511HpWz3ecmOB30PuW0vu9Y8jF9Yn3Xk22wVSy4vi1i+FHspX6YD12SqvNIsmtRoeC3wY8HoDwQlQ9+aPl4lJw1KrssPqDiwNpTvWrySScwItMNXcRHDIJOfMz4qRIVnvt+dlZEIwCz7+gwhvB20Jw26WnUezo317EQX3ODwIDAQAB
module top;endmodule
