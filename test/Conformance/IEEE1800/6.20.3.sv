// CLAUSE: parameter type
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child #(parameter type T=byte)(output T value); initial value=T'(7); endmodule
module top; int value; child #(int) d(value); initial begin #1; if(value!=7) $fatal; $display("PASS"); $finish; end endmodule
