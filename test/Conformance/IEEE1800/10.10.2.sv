// CLAUSE: concat context
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s;string a[2];
initial begin
s={"A","B"};a={"A","B"};if(s!="AB"||a[0]!="A"||a[1]!="B")$fatal(1,"concatenation context");
$display("PASS");$finish;
end
endmodule
