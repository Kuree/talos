// CLAUSE: nba captures lhs rhs
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2]; int index,value;
initial begin

  a='{0,0}; index=0; value=7;
  a[index]<=#1 value; index=1; value=9;
  #2;
  if(a[0]!=7 || a[1]!=0) $fatal(1,"NBA capture a=%p",a);

$display("PASS");
$finish;
end
endmodule
