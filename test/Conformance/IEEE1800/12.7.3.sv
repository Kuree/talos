// CLAUSE: foreach descending
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2:-1]; int result=0;
initial begin

  foreach(a[i]) result=result*10+(i+1);
  if(result!=3210) $fatal(1,"foreach direction=%0d",result);

$display("PASS");
$finish;
end
endmodule
