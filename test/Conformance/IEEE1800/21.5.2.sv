// CLAUSE: write twostate memory
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=out.hex
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{^1[aA]$}}

module top;
bit[7:0]mem[1];
initial begin
mem[0]=8'h1a;$writememh("out.hex",mem);
$display("PASS");$finish;
end
endmodule
