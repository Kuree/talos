// CLAUSE: upf_set_value_upfSupplyTypeT
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: write=1{{$}}
// CHECK: on=FULL_ON 900000 q=1{{$}}
// CHECK: off=OFF q=x{{$}}

// 1801-2018 11.2.3.3.3: an immediate write of a whole supply value. It has to reach get_supply_value and
// the domain's logic, so a function that only returns 1 fails.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT vdd;
upfSupplyTypeT value;
wire q;
leaf dut(q);
initial begin
  void'(supply_on("/top/VSS", 0.0));
  vdd = upf_get_handle_by_name("/top/VDD");
  $display("write=%0d", upf_set_value_upfSupplyTypeT(upf_query_object_properties(vdd, UPF_CURRENT_VALUE), '{FULL_ON, 900000}));
  #1;
  value = get_supply_value("/top/VDD");
  $display("on=%s %0d q=%b", value.state.name(), value.voltage, q);
  void'(upf_set_value_upfSupplyTypeT(upf_query_object_properties(vdd, UPF_CURRENT_VALUE), '{OFF, 0}));
  #1;
  value = get_supply_value("/top/VDD");
  $display("off=%s q=%b", value.state.name(), q);
  $finish;
end
endmodule
