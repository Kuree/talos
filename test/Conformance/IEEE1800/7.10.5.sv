// CLAUSE: bounded queue
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;
int q[$:2];
initial begin

  q='{10,20,30}; q.push_front(5);
  if(q.size()!=3 || q[0]!=5 || q[1]!=10 || q[2]!=20) $fatal(1,"push_front=%p",q);
  q.push_back(99);
  if(q.size()!=3 || q[2]!=20) $fatal(1,"push_back=%p",q);
  q.insert(1,7);
  if(q.size()!=3 || q[0]!=5 || q[1]!=7 || q[2]!=10) $fatal(1,"insert=%p",q);

$display("PASS");
$finish;
end
endmodule
