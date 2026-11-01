// CLAUSE: sizing relational propagation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic signed [3:0] a; logic signed [2:0] b;
initial begin
a=1; b=-4; if(!(a < -b)) $fatal(1,"a=%0d b=%0d comparison=%b",a,b,a < -b);
$display("PASS"); $finish;
end
endmodule
