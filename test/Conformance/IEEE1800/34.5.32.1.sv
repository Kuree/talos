// CLAUSE: viewport = (object, access) syntax names an object in the envelope
// XFAIL: *
// Protected envelopes are rejected by design (docs/lrm-support-roadmap.md Clause 34), and the key-file option --protect-key-file does not exist.
// RUN: %clang -c -fPIC %S/Inputs/34.5.32.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --protect-key-file=%S/Inputs/34.5.32.1/keys.json --vpi=full %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: top.seen protected={{[01]}} value=7 refused=0
// CHECK: top.hidden protected=1 value=-1 refused=1
// 34.5.32.2: viewport "describes objects within the current protected envelope for which access shall be permitted".
// 37.3.6: an object in a decryption envelope is protected, and VPI access to it is an error.

`pragma protect begin_protected
`pragma protect viewport=(object="top.seen",access="read")
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=136),data_block
B4IXnDq8ZpVn3glvT+Kya0Z9ZQl49N6iei1MU70ZB7pInVxaBuAC+UQQzPNVKDXj0US3dxfRLqWL
rFcGg8HcbApMhslEyl0AqdBBtJf3mQ3z2ovJI7rXKDOjuK9Z/FKvnmHvJBzV/tbesWqXZFp+ewGa
rDVkdxOs6LUw650CCdQRDSTVg+SQVg==
`pragma protect end_protected
