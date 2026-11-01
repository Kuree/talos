// CLAUSE: Package types retain identity across module instances
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

package P;typedef struct{int n;}T;endpackage
module leaf;P::T v;endmodule
module top;leaf a(),b();initial begin a.v.n=7;b.v=a.v;if(b.v.n!=7)$fatal(1,"shared package type");$display("PASS");$finish;end endmodule
