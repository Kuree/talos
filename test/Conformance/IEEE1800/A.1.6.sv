// CLAUSE: Function declared inside an interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface I;bit a;function int f();return a;endfunction endinterface
module top;
I i();
initial begin i.a=1;if(i.f()!=1)$fatal(1,"result"); $display("PASS");end
endmodule
