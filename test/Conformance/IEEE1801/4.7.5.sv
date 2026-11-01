// CLAUSE: Objects with power states
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_power_state'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
initial begin
if(!set_power_state("/top/CORE","RET"))$fatal(1,"deferred state");
$display("PASS");$finish;end endmodule
