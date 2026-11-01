// CLAUSE: Name references
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: references across forms: a dotted function below the scope (dut/S.power) and a domain handle function (PD.primary.power) both name the live root (IEEE 1801-2018 5.3.3.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/T.power FULL_ON 900000
// CHECK: /top/U.power FULL_ON 700000
// CHECK: /top/T.ground OFF 0

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q,r;leaf dut(q),other(r);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/S.power",0.9));void'(supply_on("/top/PD.primary.power",0.7));
show("/top/T.power");show("/top/U.power");show("/top/T.ground");
$finish;
end
endmodule
