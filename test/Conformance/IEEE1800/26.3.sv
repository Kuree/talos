// CLAUSE: wildcard local declaration shadows
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package P; int value=7; endpackage
module top; import P::*; int value=9;
initial begin if(value!=9 || P::value!=7) $fatal; $display("PASS"); $finish; end
endmodule
