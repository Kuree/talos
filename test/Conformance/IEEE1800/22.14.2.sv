// CLAUSE: keyword 1364 1995
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1364-1995"
module legacy;integer generate=7;endmodule
`end_keywords
module top;
legacy l();
initial begin
if(l.\generate !=7)$fatal;
$display("PASS");$finish;
end
endmodule
