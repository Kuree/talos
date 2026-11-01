// CLAUSE: Package and module source units
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

package P;parameter N=7;endpackage
module top;
import P::*;
initial begin if(N!=7)$fatal(1,"result"); $display("PASS");end
endmodule
