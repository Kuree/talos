// CLAUSE: real unresolved default
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

nettype real RealNet;
module top; RealNet n; wire ordinary;
initial begin #1; if(n!=0.0 || ordinary!==1'bz) $fatal; $display("PASS"); $finish; end
endmodule
