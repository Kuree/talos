// CLAUSE: get_supply_voltage
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.7/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;

initial begin
if(get_supply_voltage('{FULL_ON,700000})!=0.7)$fatal(1,"value");
$display("PASS");$finish;end endmodule
