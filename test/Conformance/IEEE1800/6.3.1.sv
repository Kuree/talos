// CLAUSE: twostate coercion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [7:0] a; bit [7:0] b;
initial begin

  a=8'b10xz01zx; b=a;
  if(b!==8'b10000100) $fatal(1,"two state actual=%b",b);

$display("PASS");
$finish;
end
endmodule
