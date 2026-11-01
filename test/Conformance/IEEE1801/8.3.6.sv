// CLAUSE: Phase 5 / query power intent model
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "upf_query_object_properties"; the command is not implemented.
// Pins: phase 5 queries the built model: a Tcl property query selects the intent, and a net named from it is visible in simulation (IEEE 1801-2018 8.3.6, 11.1.2.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/found_CORE FULL_ON 600000

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/found_CORE",0.6));
show("/top/found_CORE");
$finish;
end
endmodule
