// CLAUSE: nested keyword sets
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1800-2023"
`begin_keywords "1364-2005"
module legacy(output wire passed);
reg unique;
assign passed=unique;
initial unique=1;
endmodule
`end_keywords
module top;
bit result;
legacy l(result);
initial begin #1; if(result!==1) $fatal; $display("PASS"); $finish; end
endmodule
`end_keywords
