// CLAUSE: string case conversion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s="aBc1!";
initial begin
if(s.toupper()!="ABC1!" || s.tolower()!="abc1!" || s!="aBc1!") $fatal; if(s.icompare("AbC1!")!=0 || s.compare("aBd")>=0) $fatal;
$display("PASS"); $finish;
end
endmodule
