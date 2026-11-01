// CLAUSE: keyword 1364 2001
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1364-2001"
module legacy;integer uwire=7;endmodule
`end_keywords
module top;
legacy l();
initial begin
if(l.\uwire !=7)$fatal;
$display("PASS");$finish;
end
endmodule
