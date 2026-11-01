// CLAUSE: Modport input declaration in an interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface I;bit a;modport M(input a);endinterface
module child(I.M i);initial begin #1;if(i.a!==1)$fatal;$display("PASS");end endmodule
module top;I i();child u(i);initial i.a=1;endmodule
