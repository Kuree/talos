// CLAUSE: logic gate family
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wire a,b,c,d,e,f;and(a,1'b1,1'b0);nand(b,1'b1,1'b0);or(c,1'b1,1'b0);nor(d,1'b1,1'b0);xor(e,1'b1,1'b0);xnor(f,1'b1,1'b0);
initial begin
#1;if({a,b,c,d,e,f}!==6'b011010)$fatal;
$display("PASS");$finish;
end
endmodule
