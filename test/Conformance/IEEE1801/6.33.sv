// CLAUSE: load_upf
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: load_upf -scope runs the file once per listed instance with a fresh context, relative to the caller's scope, and restores that scope (IEEE 1801-2018 6.33, 8.3.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.33/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/wrapper/dut/rail FULL_ON 900000
// CHECK: /top/wrapper/sib/rail OFF 0
// CHECK: /top/wrapper/restored FULL_ON 600000

module leaf;endmodule
module branch;leaf dut(),sib();endmodule
module top;
import UPF::*;
branch wrapper();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/wrapper/dut/rail",0.9));void'(supply_on("/top/wrapper/restored",0.6));
show("/top/wrapper/dut/rail");show("/top/wrapper/sib/rail");show("/top/wrapper/restored");
$finish;
end
endmodule
