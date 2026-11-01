// CLAUSE: protect digest_method parser availability
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

`pragma protect digest_method="md5"
module top;endmodule
