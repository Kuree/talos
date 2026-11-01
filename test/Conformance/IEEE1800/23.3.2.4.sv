// CLAUSE: wildcard default missing identifier
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child(input int data=7,output int result); assign result=data; endmodule
module top;
int result; child u(.*);
initial begin #1; if(result!=7) $fatal; $display("PASS"); $finish; end
endmodule
