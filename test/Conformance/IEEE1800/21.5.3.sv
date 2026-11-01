// CLAUSE: write associative addresses
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=out.hex
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{@0*3}}
// FILE0-DAG: {{@0*7}}

module top;
bit[7:0]mem[int];
initial begin
mem[3]=8'h1a;mem[7]=8'h2b;$writememh("out.hex",mem);
$display("PASS");$finish;
end
endmodule
