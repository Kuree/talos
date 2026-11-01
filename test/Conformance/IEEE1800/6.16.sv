// CLAUSE: string zero removal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s; logic [23:0] v;
initial begin

  s="a\0b\0c";
  if(s!="abc" || s.len()!=3) $fatal(1,"literal NUL len=%0d",s.len());
  v=24'h410042; s=string'(v);
  if(s!="AB" || s.len()!=2) $fatal(1,"cast NUL len=%0d",s.len());
  s="\0\0"; if(s!="") $fatal(1,"all NUL");

$display("PASS");
$finish;
end
endmodule
