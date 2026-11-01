// CLAUSE: Constraint block in a class declaration
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

class C;rand int n;constraint c {n==7;}endclass
module top;
C c;
initial begin c=new;if(!c.randomize() || c.n!=7)$fatal(1,"result"); $display("PASS");end
endmodule
