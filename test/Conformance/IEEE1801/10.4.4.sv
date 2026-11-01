// CLAUSE: Relationship objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_EXTENT 1{{$}}
// CHECK: element=/top/dut{{$}}
// CHECK: object=/top/PD{{$}}
// CHECK: path=[]{{$}}

// 1801-2018 10.4.4: a relationship object links other objects, here a UPF domain to an HDL instance, and
// does not exist in the design, so it has no pathname (11.1.2.4: an empty string).
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT extent;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  extent = upf_query_object_properties(upf_get_handle_by_name("/top/PD"), UPF_EFFECTIVE_EXTENTS);
  $display("class=%s %0d", kind(extent), upf_object_in_class(extent, UPF_BASE_RELATIONSHIP));
  $display("element=%s", link(extent, UPF_HDL_ELEMENT));
  $display("object=%s", link(extent, UPF_OBJECT));
  $display("path=[%s]", upf_query_object_pathname(extent));
  $finish;
end
endmodule
