// CLAUSE: untyped mailbox type mismatch
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
mailbox m; int value,status; string text="hello",received;
initial begin

  m=new; m.put(text); value=7; status=m.try_get(value);
  if(status>=0 || value!=7 || m.num()!=1) $fatal(1,"mismatch status=%0d value=%0d count=%0d",status,value,m.num());
  status=m.try_peek(received); if(status<=0 || received!="hello" || m.num()!=1) $fatal(1,"peek status=%0d text=%s count=%0d",status,received,m.num());
  status=m.try_get(received); if(status<=0 || received!="hello" || m.num()!=0) $fatal(1,"get");

$display("PASS");
$finish;
end
endmodule
