// CLAUSE: UPF extent
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_EXTENT{{$}}
// CHECK-DAG: element=/top/m1{{$}}
// CHECK-DAG: element=/top/m2{{$}}
// CHECK: object=/top/PD{{$}}
// CHECK: count=2{{$}}
// CHECK: back=/top/PD{{$}}

// 1801-2018 10.6.3.1: the extent chain walks the resolved element list through upf_next_extent in any
// order, each link names the UPF object, and the HDL element stores a back reference in upf_extents.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire a, b;
leaf m1(a), m2(b);
upfHandleT scope;
int count = 0;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_query_object_properties(at("/top/PD"), UPF_EFFECTIVE_EXTENTS);
  $display("class=%s", kind(h));
  while (h != upf_null) begin
    count++;
    $display("element=%s", link(h, UPF_HDL_ELEMENT));
    $display("object=%s", link(h, UPF_OBJECT));
    h = upf_query_object_properties(h, UPF_NEXT_EXTENT);
  end
  $display("count=%0d", count);
  scope = at("/top/m2");
  $display("back=%s", link(upf_iter_get_next(upf_query_object_properties(scope, UPF_EXTENTS)), UPF_OBJECT));
  $finish;
end
endmodule
