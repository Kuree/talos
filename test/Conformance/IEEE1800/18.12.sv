// CLAUSE: scope randomize fixed
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int x,y;
initial begin
if(!std::randomize(x,y) with {x==7; y==9;} || x!=7 || y!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
