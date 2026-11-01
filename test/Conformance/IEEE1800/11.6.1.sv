// CLAUSE: sizing concat selfdetermined
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic signed [3:0] s; logic [3:0] a,b; logic [7:0] x,y;
initial begin
s=-1; a=15; b=1; x={s}; y={a+b}; if(x!=8'h0f || y!=0 || $bits({a+b})!=4) $fatal;
$display("PASS"); $finish;
end
endmodule
