// CLAUSE: one uniform draw matches the Annex N.2 value and next-seed vector
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int seed=30000,v;
initial begin
v=$dist_uniform(seed,-3,7);
if(v!=2 || seed!=2072070001)$fatal(1,"Annex N vector");
$display("PASS");$finish;
end
endmodule
