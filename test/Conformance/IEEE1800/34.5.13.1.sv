// CLAUSE: data_public_key syntax introduces an encoded public key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.13.1/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.13.2: "If the decrypting tool can compute the required key, the model can be decrypted".

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_method="rsa"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=294),data_public_key
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz9RyPBSpPrstHMBXQHYjV5fPU6R7RC/Q
5FZ5A13oL6vCd0eYQ4ZXq+ZpfitH4MrWnnsRUDqr7bZHTXPIcI4avPV+dAnycFjCpWg8jVZdp7+v
6dX4EQI98yunrmEu+uYc5d8QLQaFjZhjpqukhqrdhawKQTO6LHj3YNuftitz5ht2aJzZEupNUCZg
xidVSuTGoiszLiyQa1Np1xXEap6bZiHSjeX316z7mqLr59i0+GfwP2BkftZABoy11GOl+zvc8ggx
qCFT0XMNZGsI4cAEUVxIvOzBRc4gAdGHSEUUSx+H3+tjqZe0V1WQgacrH+93wwkVDRZ/6Ty8rFrW
k6318wIDAQAB
`pragma protect encoding=(enctype="base64",line_length=76,bytes=256),data_block
BQ10yzVDFRymgUbmMYpMDWbBXG0P5szZIT/YDcYrLScp/VjTNKSpN+2GpSxtD6xsu7Eh2aj/JEE6
4oxJfRCmgsN0XNm0DWgNLKjRGU7WnjMnarBNTLmL5aECpF/eYSdv5uUM1BpCRUkskaH+i5VkBSAG
CImfULewarMP5yRJCxjHZzc3dEhC/ezQKDo2glRqSJ4GssRJu82K/Tq6sIhLbZL9hoJOxtfoNDHi
PKsbBxgAYDJ/U9P/5MIlPAfdLwJtKjSQXUmsyvNLYdAl8xBpuxPcoQzzw5se3bkJ7RFBtqzKd8KA
y00Wm0wc960IdI0gORW0w5DzCKfCP1+L1p3H7g==
`pragma protect end_protected
