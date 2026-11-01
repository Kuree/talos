// CLAUSE: Power expression
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_get_value_str'; the power expression's property query is not implemented, and begin_power_model is missing too.
// Pins: -power_expr is stored with its state, and reads back unchanged through the HDL query API (IEEE 1801-2018 6.5.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: expr 3mW 4mW

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
initial begin
$display("expr %s",upf_get_value_str(upf_query_object_properties(upf_get_handle_by_name("/top/CORE.RUN"),UPF_POWER_EXPR)));
$finish;
end
endmodule
