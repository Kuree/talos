// CLAUSE: queue slice bounds
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;
int q[$]; int idx;
initial begin

  q='{10,20}; idx=3; q[idx]=99;
  if(q.size()!=2 || q[0]!=10 || q[1]!=20) $fatal(1,"invalid write changed queue");

$display("PASS");
$finish;
end
endmodule
