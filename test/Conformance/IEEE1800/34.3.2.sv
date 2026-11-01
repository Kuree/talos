// CLAUSE: Decrypted text is substituted, then its macros and nested envelopes are processed
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.3.2/keys.json %s -o %t.exe
// RUN: %t.exe
// CHECK: macro=42 inner=7
// 34.3.2: the substituted text "may contain usages of text macros" and "may also contain decryption envelopes".

`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=416),data_block
MU3gp5Yp0I5HPeUuMiZXju+ZKuVKs4f+iZZWuP2fBTe+8ZWikur3ruvECj6dB0NE7Wgus5oPl57a
q/po80cBXJ9y+bI4eb3TaIS7l+pGhC8xjIFH6EpawIQkMlcARf0PW1vf007SzgI/ogRFEPuyT0m+
BQcifQjDjq8rk80h4EXRdk/JqK6sjwjZcCUhhq1o766Md/bjpFzEizTkUs7DJI/DBJ/aROy+dqxz
PmLMs5baScj2B63mxsOP1yEYMk15xbDnuBRwrGe3CMcEL3Frnn6KY0YEsEoDdD6o5x2miQcd53U5
o/fCzaOzPADeawN6WFyWXx8Q4oJWx/yvas1F4mahqV5nzqijG9WI6lAnj0xuCYqTwxGBWs5hVH0i
mBy2Vj8ZkGcmjUyqEiXU0BZ8Y1PCbHfMgKcKrOqpOQLHQ4o37vHK5cYEJabXcsiAMKdYQcDbs+cn
oN+CzZIMPtdFsIlLjHxZmVu1KqNMvuVzeJO2UO4lTAPaQmfW9mvNzSQ6+Edl1LTpl9UD1EdXpcxJ
kLyUJVIe85oSLceowqOJ25s=
`pragma protect end_protected
