// CLAUSE: inactive before nba
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int x=0;
initial begin

  x <= 1;
  #0;
  if (x != 0) $fatal(1,"NBA committed before inactive: %0d",x);
  #1;
  if (x != 1) $fatal(1,"NBA missing: %0d",x);

$display("PASS");
$finish;
end
endmodule
