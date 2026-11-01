// CLAUSE: literal token spaces
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int v;
initial begin
v=16 'h a_b; if(v!=171) $fatal;
$display("PASS"); $finish;
end
endmodule
