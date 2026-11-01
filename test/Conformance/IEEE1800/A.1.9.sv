// CLAUSE: Constructor and method in a class body
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

class C;int n;function new(int x);n=x;endfunction function int f();return n;endfunction endclass
module top;
C c;
initial begin c=new(7);if(c.f()!=7)$fatal(1,"result"); $display("PASS");end
endmodule
