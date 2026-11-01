// CLAUSE: upf_set_value_int
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: voltage=1{{$}}
// CHECK: state=1{{$}}
// CHECK: on=FULL_ON 800000 q=1{{$}}
// CHECK: off=OFF q=x{{$}}

// 1801-2018 11.2.3.3.2: an immediate write to a dynamic property, using its example's fields. The write
// has to reach the standard read function and power the domain's logic on and off.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT vdd, supplyValue, voltage, state;
upfSupplyTypeT value;
wire q;
leaf dut(q);
initial begin
  void'(supply_on("/top/VSS", 0.0));
  vdd = upf_get_handle_by_name("/top/VDD");
  supplyValue = upf_query_object_properties(vdd, UPF_CURRENT_VALUE);
  voltage = upf_query_object_properties(supplyValue, UPF_VOLTAGE);
  state = upf_query_object_properties(supplyValue, UPF_STATE);
  $display("voltage=%0d", upf_set_value_int(voltage, 800000));
  $display("state=%0d", upf_set_value_int(state, FULL_ON));
  #1;
  value = get_supply_value("/top/VDD");
  $display("on=%s %0d q=%b", value.state.name(), value.voltage, q);
  void'(upf_set_value_int(upf_query_object_properties(upf_query_object_properties(vdd, UPF_CURRENT_VALUE), UPF_STATE), OFF));
  #1;
  value = get_supply_value("/top/VDD");
  $display("off=%s q=%b", value.state.name(), q);
  $finish;
end
endmodule
