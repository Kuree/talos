// CLAUSE: HDL interface
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import UPF::*;
upfSupplyTypeT s;
initial begin
void'(supply_on("/top/VDD",0.7));
s=get_supply_value("/top/VDD");
if(s.state!=FULL_ON || s.voltage!=700000)$fatal(1,"supply snapshot");
$display("PASS");$finish;
end
endmodule
