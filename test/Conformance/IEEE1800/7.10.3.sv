// CLAUSE: queue ref insert
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  int q[$];
  task automatic modify(ref int value);
    q.push_front(5); q.insert(1,6); value=77;
  endtask

initial begin

  q='{10,20,30}; modify(q[1]);
  if(q.size()!=5 || q[3]!=77 || q[1]!=6 || q[2]!=10) $fatal(1,"persistent ref q=%p",q);

$display("PASS");
$finish;
end
endmodule
