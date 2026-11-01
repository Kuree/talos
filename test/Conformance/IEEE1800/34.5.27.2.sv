// CLAUSE: A key_block decrypts to the data key and method; a key_block outside an envelope is rejected
// XFAIL: *
// The driver has no decryption path and no --protect-keys option, and a stray key_block gets only the generic envelope message.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/34.5.27.2/outside.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-keys=%S/Inputs/34.5.27.2/public-key.json %s -o %t.exe
// RUN: %t.exe
// DIAG: key_block
// CHECK: decrypted 42{{$}}

// 34.5.27.2: only the key_block knows the data key, so printing the computed value needs both decrypt steps.
// Public DES test key for the key_block: 0123456789abcdef.
`pragma protect begin_protected
`pragma protect key_keyowner="lrm-audit"
`pragma protect key_keyname="exchange-key"
`pragma protect key_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=152)
`pragma protect key_block
EjRWeJCrze8ITCU8fvqLT9PgSvOcPMtNpKoo30E+wQeqCxtYkeFSVUv5sd14FvlfTjAy4yPCGF/e
au/vIFskbIUutf4I9O42/dVjpoI355OSHZJBJLiNmI1yFhB7cpnQxMGF3zTZIowqbMPes2XBPHDb
zGEzarDloHD3aYCffmm39UB5B3zjQw4G01T6q/Vpu/csmhl2yeI=
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=96)
`pragma protect data_block
ABEiM0RVZncct2lmI3vDBHpB9Mi7Nu0X+LbOXtJ51fnXB9LlR2OcjDg30Rr8OMbRjoD5aPUAORCA
Nfp+yZxFEq15XIkXy6fgjFtmFYoesLIEeZamh4+oh24qzuUWQKk1
`pragma protect end_protected
