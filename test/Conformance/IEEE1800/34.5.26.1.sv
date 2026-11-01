// CLAUSE: key_public_key syntax introduces an encoded public key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.26.1/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.26.2: "If the decrypting tool can compute the required key, the data keys can be decrypted."

`pragma protect begin_protected
`pragma protect key_keyowner="lrm-audit"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=294),key_public_key
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz9RyPBSpPrstHMBXQHYjV5fPU6R7RC/Q
5FZ5A13oL6vCd0eYQ4ZXq+ZpfitH4MrWnnsRUDqr7bZHTXPIcI4avPV+dAnycFjCpWg8jVZdp7+v
6dX4EQI98yunrmEu+uYc5d8QLQaFjZhjpqukhqrdhawKQTO6LHj3YNuftitz5ht2aJzZEupNUCZg
xidVSuTGoiszLiyQa1Np1xXEap6bZiHSjeX316z7mqLr59i0+GfwP2BkftZABoy11GOl+zvc8ggx
qCFT0XMNZGsI4cAEUVxIvOzBRc4gAdGHSEUUSx+H3+tjqZe0V1WQgacrH+93wwkVDRZ/6Ty8rFrW
k6318wIDAQAB
`pragma protect encoding=(enctype="base64",line_length=76,bytes=256),key_block
HAQTQyZVs5xcN8BJU7XLmSqNxbuIamGyw+WiSPTnc7TPkm+VAln3gv0Ep8H7ZV8FWqVRNHC960nU
B6OK4n07M0vWgAN2K04dUS8wyXl5L5xXBFgn3+tr+jg6kIDMceUVVEfQkQpfCyTQvW8wwigq7foR
9Hqvfv5x8PuRyP/mS7Jgz4ylO4l9FwmxDgM77lBe4imLmFQln8O3VWpbSzVJ6UTos7FOjyQW9bC6
3dkFlt+73z/cGVi6gYpHn7yk0ZJ0owZhlvDnudwLba3VmT5vNaTYlQW4HozUsb1698FvXY8u6oUI
TKJh8x5UiFHeaLjZ1xXBAYs7bQ17R0sVqMnxHg==
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbc49zCO5k/jJ7bS+kh255+Hr/n0qfKxR0SG9l22EuSiCOnbYK+vv6xHT3AQCfPN/i0
Jy5ZBHzaSk09DhnXVKa1qa8F7emKls9prd9diQUh2C/UfA25aLuz
`pragma protect end_protected
