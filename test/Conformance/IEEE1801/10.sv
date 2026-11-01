// CLAUSE: UPF information model
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_SUPPLY_NET{{$}}
// CHECK: name=VDD{{$}}
// CHECK: line=1{{$}}
// CHECK: path=/top/VDD{{$}}
// CHECK: value=FULL_ON 800000{{$}}

// 1801-2018 10.1, 10.2: the power intent is a model of objects and properties read through the
// HDL package. One supply net is created in UPF, then read back with its static and dynamic properties.
module top;
import UPF::*;
upfHandleT net;
upfSupplyTypeT value;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
initial begin
  net = upf_get_handle_by_name("/top/VDD");
  $display("class=%s", kind(net));
  $display("name=%s", text(net, UPF_NAME));
  $display("line=%0d", number(net, UPF_LINE));
  $display("path=%s", upf_query_object_pathname(net));
  void'(supply_on("/top/VDD", 0.8));
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("value=%s %0d", value.state.name(), value.voltage);
  $finish;
end
endmodule
