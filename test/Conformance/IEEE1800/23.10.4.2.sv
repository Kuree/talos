// CLAUSE: reject hierarchical defparam whose resolution changes during elaboration
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;M n();endmodule
module M;parameter p=2;defparam top.n.p=1;
if(p==1)begin:top N n();end endmodule
module N;parameter p=3;endmodule
