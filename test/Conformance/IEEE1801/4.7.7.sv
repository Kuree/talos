// CLAUSE: Power states and power dissipation
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_get_value_str'; the power expression's property query is not implemented, and begin_power_model is missing too.
// Pins: a power expression has no simulated effect, so its value is read back through the HDL query API (IEEE 1801-2018 4.7.7, 11.2.3.1.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: expr 1mW 2mW

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
initial begin
$display("expr %s",upf_get_value_str(upf_query_object_properties(upf_get_handle_by_name("/top/dut.RUN"),UPF_POWER_EXPR)));
$finish;
end
endmodule
