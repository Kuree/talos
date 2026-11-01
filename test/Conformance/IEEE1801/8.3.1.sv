// CLAUSE: Liberty import and recursive UPF loading
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: recursive loading: a loaded file loads another, and each resolves in its own scope. Liberty import has no compiler entry point and is not exercised (IEEE 1801-2018 8.3.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/sub/rail FULL_ON 900000
// CHECK: /top/dut/mid FULL_ON 700000
// CHECK: /top/outer FULL_ON 600000

module leaf;endmodule
module branch;leaf sub();endmodule
module top;
import UPF::*;
branch dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/sub/rail",0.9));void'(supply_on("/top/dut/mid",0.7));void'(supply_on("/top/outer",0.6));
show("/top/dut/sub/rail");show("/top/dut/mid");show("/top/outer");
$finish;
end
endmodule
