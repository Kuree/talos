// CLAUSE: Protected-flow examples
// XFAIL: *
// Protected envelopes are rejected by design (Clause 34 is deliberately unsupported), so this flow has no decryption path.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

// IEEE 1800-2023 34.3,34.5.11 Table 34-3,34.5.15.
// The public fixture key is supplied in public-key.json.
`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=80)
`pragma protect data_block
EjRWeJCrze9/6icnxeWP25OLQhsO6GdiB9LbWfvvJXUcL8e6hquVx6KsHTAeVMKBhnjgIScYa6D/
o6DKBgCfJx5O74eGpO5/F6jMwyWLBXY=
`pragma protect end_protected
