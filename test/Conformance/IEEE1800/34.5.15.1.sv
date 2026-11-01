// CLAUSE: reject data_block outside an existing protected envelope
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

`pragma protect encoding=(enctype="base64",bytes=8)
`pragma protect data_block
AAAAAAAAAAA=
module top;endmodule
