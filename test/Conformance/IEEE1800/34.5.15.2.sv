// CLAUSE: A data_block decrypts and runs; a data_block outside a protected envelope is rejected
// XFAIL: *
// The driver has no decryption path and no --protect-keys option, and a stray data_block gets only the generic envelope message.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/34.5.15.2/outside.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-keys=%S/Inputs/34.5.15.2/public-key.json %s -o %t.exe
// RUN: %t.exe
// DIAG: data_block
// CHECK: decrypted 42{{$}}

// 34.5.15.2: the block holds a design printing a computed value, so only a real decrypt and run can print it.
// Public DES test key: 0123456789abcdef.
`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96)
`pragma protect data_block
EjRWeJCrze9/6icnxeWP25OLQhsO6GdiB9LbWfvvJXUcL8e6hquVx7R+cKmQzTSE2/2Iefd6levf
qh8RDzuzxQtPDc2JrTTvFrRmXsVUTkJncYqvfpjKEFhgRltQI9LO
`pragma protect end_protected
