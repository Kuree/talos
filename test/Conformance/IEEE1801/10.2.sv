// CLAUSE: Components of UPF information model
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: upf=PD{{$}}
// CHECK: hdl=dut{{$}}
// CHECK: relationship=/top/dut{{$}}

// 1801-2018 10.2.1: the model is objects and the properties on them. Read one property from an object
// of each group; the relationship object ties the domain to the instance in its extent.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT domain, scope, extent;
wire q;
leaf dut(q);
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  domain = upf_get_handle_by_name("/top/PD");
  scope = upf_get_handle_by_name("/top/dut");
  extent = upf_query_object_properties(domain, UPF_EFFECTIVE_EXTENTS);
  $display("upf=%s", text(domain, UPF_NAME));
  $display("hdl=%s", text(scope, UPF_NAME));
  $display("relationship=%s", link(extent, UPF_HDL_ELEMENT));
  $finish;
end
endmodule
