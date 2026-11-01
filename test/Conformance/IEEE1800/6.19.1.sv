// CLAUSE: enum cast failure retains value
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef enum int {A=1,B=2} E; E e; int status,v;
initial begin

  e=A; v=3; status=$cast(e,v);
  if(status!=0 || e!=A) $fatal(1,"failed cast status=%0d e=%0d",status,e);
  v=2; status=$cast(e,v);
  if(status!=1 || e!=B) $fatal(1,"successful cast");

$display("PASS");
$finish;
end
endmodule
