// CLAUSE: unknown conditional merge
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic c; logic [3:0] a,b,v;
initial begin

  c=1'bx; a=4'b1100; b=4'b1010; v=c?a:b;
  if(v!==4'b1xx0) $fatal(1,"conditional merge=%b",v);

$display("PASS");
$finish;
end
endmodule
