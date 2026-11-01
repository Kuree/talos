// CLAUSE: semaphore try get
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
semaphore s; int status;
initial begin

  s=new(2);
  status=s.try_get(3); if(status!=0) $fatal(1,"insufficient keys");
  status=s.try_get(2); if(status!=1) $fatal(1,"failed get");
  status=s.try_get(1); if(status!=0) $fatal(1,"get consumed wrong number");
  s.put(1); if(s.try_get(1)!=1) $fatal(1,"put");

$display("PASS");
$finish;
end
endmodule
