// CLAUSE: do while executes once for an initially false condition
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;int n=0;
initial begin
  do n++; while (0);
  if(n!=1)$fatal(1,"do while executes once");
  $display("PASS");$finish;
end endmodule
