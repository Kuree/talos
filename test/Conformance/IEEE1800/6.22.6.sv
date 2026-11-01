// CLAUSE: matching nettypes
// XFAIL: *
// The frontend rejects package-qualified user-defined nettype aliases as non-types.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package p;nettype logic N;nettype N M;endpackage
module dut_unit(input p::N n,output wire y);assign y=n;endmodule
module top;p::M n;wire y;assign n=1;dut_unit d(n,y);initial begin #1;if(y!==1)$fatal(1,"nettype alias");$display("PASS");$finish;end endmodule
