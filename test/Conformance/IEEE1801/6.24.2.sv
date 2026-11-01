// CLAUSE: Supply net resolution
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: the first UPF slice supports unresolved supply nets, so -resolve one_hot is refused.
// Pins: an unresolved net with two sources is an error; declaring a resolution method makes the design legal, and the net then follows its one active source (IEEE 1801-2018 6.24.2).
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.2/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/N FULL_ON 900000
// CHECK: /top/N OFF 0
// CHECK: /top/N FULL_ON 800000
// DIAG: multiple

module top;
import UPF::*;
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/A",0.9));show("/top/N");
void'(supply_off("/top/A"));show("/top/N");
void'(supply_on("/top/B",0.8));show("/top/N");
$finish;
end
endmodule
