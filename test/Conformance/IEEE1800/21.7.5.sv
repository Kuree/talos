// CLAUSE: vcd type mapping
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.vcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$var[[:space:]]+reg[[:space:]]+1[[:space:]]+[^[:space:]]+[[:space:]]+b}}
// FILE0-DAG: {{\$var[[:space:]]+integer[[:space:]]+32[[:space:]]+[^[:space:]]+[[:space:]]+n}}

module top;
bit b=1;int n=7;
initial begin
$dumpfile("probe.vcd");$dumpvars(0,b,n);#1;
$display("PASS");$finish;
end
endmodule
