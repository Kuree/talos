// CLAUSE: upf_get_label_upfSupplyTypeT
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=1{{$}}
// CHECK: on=FULL_ON 900000{{$}}
// CHECK: off=OFF{{$}}

// 1801-2018 11.2.3.2.5: the upfSupplyTypeT value of a supply's property, as in its example, at two times
// so that a fixed answer fails.
module top;
import UPF::*;
upfHandleT net, value;
upfSupplyTypeT snet;
initial begin
  net = upf_get_handle_by_name("/top/VDD@upfSupplyNetT");
  value = upf_query_object_properties(net, UPF_CURRENT_VALUE);
  $display("class=%0d", upf_object_in_class(value, UPF_SUPPLY_TYPE));
  void'(supply_on("/top/VDD", 0.9));
  #1;
  snet = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("on=%s %0d", snet.state.name(), snet.voltage);
  void'(supply_off("/top/VDD"));
  #1;
  snet = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("off=%s", snet.state.name());
  $finish;
end
endmodule
