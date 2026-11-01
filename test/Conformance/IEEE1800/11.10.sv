// CLAUSE: literal string concat
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s;
initial begin
s={"ab","cd"};if(s!="abcd")$fatal(1,"literal concatenation");
$display("PASS");$finish;
end
endmodule
