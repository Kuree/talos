// CLAUSE: Type and constant declarations in a package
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

package P;typedef bit[2:0]T;parameter T N=5;endpackage
module top;
P::T n;
initial begin n=P::N;if(n!=5 || $bits(n)!=3)$fatal(1,"result"); $display("PASS");end
endmodule
