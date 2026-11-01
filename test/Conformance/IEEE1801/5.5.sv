// CLAUSE: Object declaration
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a declaration colliding with an existing name is an error and leaves the existing net; the failed set does not exist (IEEE 1801-2018 5.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: /top/rail FULL_ON 900000
// CHECK-DAG: /top/collided FULL_ON 700000
// CHECK-DAG: set function=0
// CHECK-DAG: UPF supply control failed for /top/rail.power

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/rail",0.9));void'(supply_on("/top/collided",0.7));
show("/top/rail");show("/top/collided");
$display("set function=%b",supply_on("/top/rail.power"));
$finish;
end
endmodule
