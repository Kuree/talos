// CLAUSE: Dynamic properties
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.2.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: start=OFF{{$}}
// CHECK: on=FULL_ON 900000{{$}}
// CHECK: off=OFF{{$}}

// 1801-2018 10.2.3.2: a dynamic property follows the simulation. The same object's current value has
// to change as the supply is written, which a static snapshot of the model would not show.
module top;
import UPF::*;
upfHandleT net;
upfSupplyTypeT value;
initial begin
  net = upf_get_handle_by_name("/top/VDD");
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("start=%s", value.state.name());
  void'(supply_on("/top/VDD", 0.9));
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("on=%s %0d", value.state.name(), value.voltage);
  void'(supply_off("/top/VDD"));
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("off=%s", value.state.name());
  $finish;
end
endmodule
