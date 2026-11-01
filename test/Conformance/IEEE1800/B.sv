// CLAUSE: Keyword modes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1364-2001"
module legacy; integer logic=5; endmodule
`end_keywords
module top; legacy l();int \class ;initial begin \class =9;
 if(l.\logic !=5 || \class !=9) $fatal(1,"keyword revision");$display("PASS");$finish;
end endmodule
