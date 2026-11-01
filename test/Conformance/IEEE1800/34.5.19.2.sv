// CLAUSE: The tool combines owner, method and digest_public_key to find the private key
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.19.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: decrypted x=42
// 34.5.19.2: "If the decrypting tool can compute the required key, the model can be decrypted".

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect digest_keyowner="lrm-audit"
`pragma protect digest_key_method="rsa"
`pragma protect digest_method="md5"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=294),digest_public_key
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz9RyPBSpPrstHMBXQHYjV5fPU6R7RC/Q
5FZ5A13oL6vCd0eYQ4ZXq+ZpfitH4MrWnnsRUDqr7bZHTXPIcI4avPV+dAnycFjCpWg8jVZdp7+v
6dX4EQI98yunrmEu+uYc5d8QLQaFjZhjpqukhqrdhawKQTO6LHj3YNuftitz5ht2aJzZEupNUCZg
xidVSuTGoiszLiyQa1Np1xXEap6bZiHSjeX316z7mqLr59i0+GfwP2BkftZABoy11GOl+zvc8ggx
qCFT0XMNZGsI4cAEUVxIvOzBRc4gAdGHSEUUSx+H3+tjqZe0V1WQgacrH+93wwkVDRZ/6Ty8rFrW
k6318wIDAQAB
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96),data_block
16xOf2gocWbrgrPf7yNN2+cdXmutqKjv67k7IXbtyJPhRj9jwSRu/40Lj8VRVRViKr5bIq9lPYIn
cwk0z3dhttNcw6NLcTXLUfeI5iRdiAB1TC9trvRPO4ktyE00Xu84
`pragma protect encoding=(enctype="base64",line_length=76,bytes=256),digest_block
lrUKYcdKLgFQscCkRzQDFl/KLHmCPu7UGVSTNEDPECiNU15nvuaC+jMgwVge80zgwk7nyZw/2YuF
00o19eig2FnbegWvYjbbQDOqfINrTT4i9MWJFVmCqOW28LVHo4QD+3cRIFWROgAALGfpkin7Xs/t
53+8ViVxJ7iVbLdXbQVoA/1dR2anE3VBCekUb07SAA4nSSf1OIM3VG/PkEh7NbkF2QQkDCvUBJKU
t6sfe4vJm+SNA+2YBUJ1/FXAV2xXejcb3OMWzPHYnplNSi3knSGCGyr9V2okTe9yk5L3cUDUUD58
Z5MeNRjljyhKSejWKjQyPRc03L53WL0di/XKwg==
`pragma protect end_protected
