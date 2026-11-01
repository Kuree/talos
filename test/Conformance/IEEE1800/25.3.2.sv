// CLAUSE: Interface variables are shared through bundle ports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface bus;int value;endinterface
module leaf(bus p);initial p.value=7;endmodule
module top;bus b();leaf d(b);initial begin #1;if(b.value!=7)$fatal(1,"interface reference");$display("PASS");$finish;end endmodule
