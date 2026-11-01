// CLAUSE: Randomize
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int x;
initial begin
if(!std::randomize(x) with {x==7;} || x!=7)$fatal(1,"std randomize");
$display("PASS");$finish;
end
endmodule
