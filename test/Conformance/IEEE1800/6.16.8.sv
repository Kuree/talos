// CLAUSE: string putc and bounds
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s;
initial begin

  s="abc"; s.putc(1,0); s[0]=0; s.putc(-1,65); s[3]=65;
  if(s!="abc" || s[-1]!=0 || s[3]!=0) $fatal(1,"putc/bounds actual=%s",s);
  if(s.substr(-1,1)!="" || s.substr(1,3)!="" || s.substr(2,1)!="" || s.substr(1,2)!="bc")
    $fatal(1,"substr bounds");

$display("PASS");
$finish;
end
endmodule
