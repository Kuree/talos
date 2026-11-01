// CLAUSE: UPF ports and nets with same name
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import UPF::*;
upfSupplyTypeT sample;
initial begin
if(!supply_on("/top/PAD"))$fatal(1,"port supply");
sample=get_supply_value("/top/VDD");
if(sample.state!=FULL_ON)$fatal(1,"connected net value");
$display("PASS");$finish;
end
endmodule
