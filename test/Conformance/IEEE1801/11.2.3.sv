// CLAUSE: HDL access functions
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=VDD{{$}}
// CHECK: first=UPF_NAMED_REF{{$}}
// CHECK: write=1{{$}}
// CHECK: read=FULL_ON 800000{{$}}
// CHECK: class=UPF_SUPPLY_NET 1{{$}}
// CHECK: path=/top/VDD{{$}}

// 1801-2018 11.2.3: one use from each family of access functions: object and property access, the iterator,
// immediate write and read, and the utilities.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT net, functions;
upfSupplyTypeT value;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
initial begin
  net = upf_get_handle_by_name("/top/VDD");
  $display("name=%s", text(net, UPF_NAME));
  functions = upf_query_object_properties(upf_get_handle_by_name("/top/CORE"), UPF_FUNCTIONS);
  $display("first=%s", kind(upf_iter_get_next(functions)));
  $display("write=%0d", upf_set_value_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE), '{FULL_ON, 800000}));
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(net, UPF_CURRENT_VALUE));
  $display("read=%s %0d", value.state.name(), value.voltage);
  $display("class=%s %0d", kind(net), upf_object_in_class(net, UPF_NET_CLASS));
  $display("path=%s", upf_query_object_pathname(net));
  $finish;
end
endmodule
