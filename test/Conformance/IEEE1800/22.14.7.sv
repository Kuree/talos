// CLAUSE: keyword 1800 2009
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`begin_keywords "1800-2009"
module legacy;integer soft=7;endmodule
`end_keywords
module top;
legacy l();
initial begin
if(l.\soft !=7)$fatal;
$display("PASS");$finish;
end
endmodule
