// CLAUSE: conditional directive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define YES
`ifdef NO
`define V 1
`elsif YES
`define V 2
`else
`define V 3
`endif
module top;

initial begin
if(`V!=2)$fatal;
$display("PASS");$finish;
end
endmodule
