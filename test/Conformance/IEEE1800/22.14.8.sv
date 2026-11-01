// CLAUSE: keyword 1800 2012
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1800-2012"
module top;logic b=1;initial begin if(!b)$fatal;$display("PASS");$finish;end endmodule
`end_keywords
