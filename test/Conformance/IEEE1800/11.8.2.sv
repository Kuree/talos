// CLAUSE: context width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [7:0] a,b; logic [8:0] c;
initial begin

  a=8'hff; b=8'h01; c=(a+b)>>1;
  if(c!==9'h080) $fatal(1,"context c=%h",c);

$display("PASS");
$finish;
end
endmodule
