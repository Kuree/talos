// CLAUSE: key_public_key identifies the private key that decrypts the key_block
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.26/keys.json %s -o %t.exe
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
VVY9wdI56/uvnNOIjbhYwi1bcc3/kdh/fy3kfs1fQSY88nSAPpOpWwbiLmZC/o0IZ9IA9TiCxiym
vXGIS97tBWD9ggs6lLMVClPigfTLlaiCkEy70ruUdIXaxxNHgfEetO59WxCRVCSX30jQrbGt+M2K
a9pXFrC3Pj6YEwUC6xU/GmiPwdmg9u1A1yVEitfCziek745GobcLM7Hwe01kFesX5zUQ47ubB+QJ
MpNIMB52J7/K9Y7QuM5avFh5QGsIdd3JdiubLuraCH1piQDIbjlZ1tmA8ob/JpmsAqk5J95xZv9Y
DC9WX+kewZByU0DLO6JTWCeHdqi8bCIKVYdihg==
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbc49zCO5k/jJ7bS+kh255+Hr/n0qfKxR0SG9l22EuSiCOnbYK+vv6xHT3AQCfPN/i0
Jy5ZBHzaSk09DhnXVKa1qa8F7emKls9prd9diQUh2C/UfA25aLuz
`pragma protect end_protected
