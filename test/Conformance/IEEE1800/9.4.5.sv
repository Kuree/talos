// CLAUSE: blocking delayed lhs resolution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2]; int index=0,value=7;
initial begin

  a='{0,0};
  fork begin a[index]=#2 value; end begin #1; index=1; value=9; end join
  if(a[0]!=0 || a[1]!=7) $fatal(1,"blocking intra-delay a=%p",a);

$display("PASS");
$finish;
end
endmodule
