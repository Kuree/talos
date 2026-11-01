// CLAUSE: Hierarchy navigation
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: navigation: set_scope descends by a relative path and climbs with "..", but cannot leave the design top (IEEE 1801-2018 4.3.7, 6.52).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.3.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/child/deep FULL_ON 1000000
// CHECK: /top/dut/mid FULL_ON 800000
// CHECK: /top/stop FULL_ON 600000

module leaf;endmodule
module branch;leaf child();endmodule
module top;
import UPF::*;
branch dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/child/deep"));void'(supply_on("/top/dut/mid",0.8));void'(supply_on("/top/stop",0.6));
show("/top/dut/child/deep");show("/top/dut/mid");show("/top/stop");
$finish;
end
endmodule
