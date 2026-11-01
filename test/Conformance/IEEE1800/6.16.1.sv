// CLAUSE: string len
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s="abc";
initial begin
if(s.len()!=3)$fatal(1,"string length");
$display("PASS");$finish;
end
endmodule
