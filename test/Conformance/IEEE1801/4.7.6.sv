// CLAUSE: Power states as constraints
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: states constrain operation: an active -illegal state is a reported error, and -complete closes the catalog (IEEE 1801-2018 4.7.6, 6.5.6, 9.3.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: legal q=1
// CHECK-DAG: illegal q=1
// CHECK-DAG: /top/closed FULL_ON 500000
// CHECK-DAG: UPF supply set /top/CORE: illegal power state

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/closed",0.5));
#1;$display("legal q=%b",q);
void'(supply_on("/top/VDD",0.8));#1;$display("illegal q=%b",q);
show("/top/closed");
$finish;
end
endmodule
