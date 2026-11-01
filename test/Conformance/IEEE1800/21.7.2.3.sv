// CLAUSE: vcd keyword commands
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.vcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$date}}
// FILE0-DAG: {{\$version}}
// FILE0-DAG: {{\$timescale}}
// FILE0-DAG: {{\$scope}}
// FILE0-DAG: {{\$upscope}}
// FILE0-DAG: {{\$enddefinitions}}
// FILE0-DAG: {{\$dumpvars}}

module top;
logic q=0;
initial begin
$dumpfile("probe.vcd");$dumpvars(0,q);#1;q=1;#1;
$display("PASS");$finish;
end
endmodule
