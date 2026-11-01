// CLAUSE: set_supply_state
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_supply_state'; did you mean 'get_supply_state'?
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
initial begin
if(!set_supply_state("/top/VDD",FULL_ON))$fatal(1,"set state");
if(get_supply_state(get_supply_value("/top/VDD"))!=FULL_ON)$fatal(1,"state");
$display("PASS");$finish;end endmodule
