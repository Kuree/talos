// CLAUSE: Supply net resolution
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: the first UPF slice supports unresolved supply nets, so -resolve one_hot is refused.
// Pins: one_hot resolution: one active source drives the net, and two active sources are UNDETERMINED (IEEE 1801-2018 4.5.4.4, 6.24.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.4.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK: /top/N OFF 0
// CHECK: /top/N FULL_ON 900000
// CHECK: /top/N UNDETERMINED

module top;
import UPF::*;
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
show("/top/N");
void'(supply_on("/top/A",0.9));show("/top/N");
void'(supply_on("/top/B",0.9));show("/top/N");
$finish;
end
endmodule
