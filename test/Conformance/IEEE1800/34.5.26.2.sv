// CLAUSE: The tool combines owner, method and key_public_key to find the private key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.26.2/keys.json %s -o %t.exe
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
y/E0JMxzRnRSpe0hn5KPa7c9gCqkCoyndPxyncBqkWQkqdq+HLmc7Gv7kJi2H84xu6izz0rNtu3q
gp4RgEs1nHei1aN9Y8VIBt/tTrAkZo5QukJaqk/On6L/Wv69LoPw1Q0/q9jMthCpgn+RCI1FxbZx
LYYUOvB8mikA9ya3PJl9i6wd1RZpozg+AKmsrsMG1gPJ8LOXWlNAwRawXPxSs19CUDDqoquCKO+t
AkFQOHUoe9PQUAm45tBGjynz+X3aDEA3ZzOIkUi9IhKLttqTqvhxp4xFUAyO4KMfRbMvUZWO66Wn
iiAwOfIU8O/p3gZTmIGEZwgQXoXtVCNlZLdcPQ==
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbc49zCO5k/jJ7bS+kh255+Hr/n0qfKxR0SG9l22EuSiCOnbYK+vv6xHT3AQCfPN/i0
Jy5ZBHzaSk09DhnXVKa1qa8F7emKls9prd9diQUh2C/UfA25aLuz
`pragma protect end_protected
