// CLAUSE: Escaped character inside a string literal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
string s="a\nb";
initial begin if(s.len()!=3 || s[1]!=10)$fatal(1,"result"); $display("PASS");end
endmodule
