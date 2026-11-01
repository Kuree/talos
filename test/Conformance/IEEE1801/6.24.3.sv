// CLAUSE: Resolution methods
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: the first UPF slice supports unresolved supply nets, so -resolve parallel is refused.
// Pins: parallel resolution: the net is on while any source is on, and OFF only when all are; one_hot in the same design is not (IEEE 1801-2018 6.24.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/N FULL_ON 900000
// CHECK: /top/N FULL_ON 900000
// CHECK: /top/N OFF 0

module top;
import UPF::*;
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/A",0.9));void'(supply_on("/top/B",0.9));show("/top/N");
void'(supply_off("/top/A"));show("/top/N");
void'(supply_off("/top/B"));show("/top/N");
$finish;
end
endmodule
