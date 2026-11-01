// CLAUSE: dynamic ref resize detaches
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;
int a[]; int size;
initial begin

  if(!$value$plusargs("size=%d",size)) size=-1;
  a=new[size];

$display("PASS");
$finish;
end
endmodule
