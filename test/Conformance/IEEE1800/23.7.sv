// CLAUSE: member hierarchical select
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;typedef struct{int value;}T;T data='{7};endmodule
module top;leaf d();initial begin if(d.data.value!=7)$fatal;$display("PASS");$finish;end endmodule
