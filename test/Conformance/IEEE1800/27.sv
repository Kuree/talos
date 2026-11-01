// CLAUSE: Generate scopes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
for(genvar i=2;i<9;i+=3) begin:g localparam int v=i; end
initial begin
if(g[2].v!=2 || g[5].i!=5 || g[8].v!=8 || $bits(g[5].i)!=32) $fatal;
$display("PASS"); $finish;
end
endmodule
