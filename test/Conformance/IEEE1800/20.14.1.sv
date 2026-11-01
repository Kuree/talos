// CLAUSE: random seed replay
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a=3,b=3,x,y;
initial begin
x=$random(a);y=$random(b);if(x!=y || a!=b)$fatal;
$display("PASS");$finish;
end
endmodule
