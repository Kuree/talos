// CLAUSE: default queue min
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {int v=7;} S; S q[$]; S r;
initial begin
r=q.pop_front(); if(r.v!=7) $fatal(1,"actual=%0d",r.v);
$display("PASS"); $finish;
end
endmodule
