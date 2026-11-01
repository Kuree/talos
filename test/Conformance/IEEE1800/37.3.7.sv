// CLAUSE: Static VPI handles remain usable across simulation time
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.3.7/lifetime.c -I%resource_dir/include -o %t.lifetime.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full %s %t.lifetime.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int value=3;import "DPI-C" context function int cached();
initial begin
if(cached()!=3)$fatal;#1;value=7;if(cached()!=7)$fatal(1,"static handle lifetime");
$display("PASS");$finish;
end
endmodule
