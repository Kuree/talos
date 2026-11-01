// CLAUSE: HDL scope
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_HDL_SCOPE{{$}}
// CHECK: name=dut{{$}}
// CHECK: parent=/top{{$}}
// CHECK: item=/top/dut/PD{{$}}
// CHECK: domain=/top/dut/PD{{$}}
// CHECK: port=/top/dut/q{{$}}
// CHECK: child=/top/dut/mid{{$}}
// CHECK: extent=/top/dut/PD{{$}}

// 1801-2018 10.6.2.1: an instance in the logic hierarchy, with the children and back references in its
// example table. upf_items is unordered, so a plain CHECK skips the other objects created in this scope.
module inner(output logic q);
  assign q = 1;
endmodule
module leaf(output wire q);
  inner mid(q);
endmodule
module top;
import UPF::*;
upfHandleT h;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = at("/top/dut");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  each("item", upf_query_object_properties(h, UPF_ITEMS));
  each("domain", upf_query_object_properties(h, UPF_POWER_DOMAINS));
  each("port", upf_query_object_properties(h, UPF_HDL_PORTS));
  each("child", upf_query_object_properties(h, UPF_CHILD_INSTANCES));
  $display("extent=%s", link(upf_iter_get_next(upf_query_object_properties(h, UPF_EXTENTS)), UPF_OBJECT));
  $finish;
end
endmodule
