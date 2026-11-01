// CLAUSE: vcd value formats
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.vcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{^0[^[:space:]]+}}
// FILE0-DAG: {{^1[^[:space:]]+}}
// FILE0-DAG: {{^bxz[[:space:]]+[^[:space:]]+}}
// FILE0-DAG: {{^b10[[:space:]]+[^[:space:]]+}}
// FILE0-DAG: {{^r1.25[[:space:]]+[^[:space:]]+}}

module top;
logic q=0;logic[1:0]v=2'bxz;real r=1.25;
initial begin
$dumpfile("probe.vcd");$dumpvars(0,q,v,r);#1;q=1;v=2'b10;r=2.5;#1;
$display("PASS");$finish;
end
endmodule
