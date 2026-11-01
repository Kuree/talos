// CLAUSE: formfeed tokens
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module
top;
int
v;
initial begin v=7; if(v!=7) $fatal; $display("PASS"); $finish; end
endmodule
