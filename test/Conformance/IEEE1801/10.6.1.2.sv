// CLAUSE: Retention strategy
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_RETENTION_STRATEGY{{$}}
// CHECK: name=KEEP{{$}}
// CHECK: parent=/top/PD{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=7{{$}}
// CHECK: scope=/top{{$}}
// CHECK: element=/top/dut/state{{$}}
// CHECK-DAG: handle=/top/PD.KEEP.retention_supply{{$}}
// CHECK-DAG: handle=/top/PD.KEEP.primary_supply{{$}}
// CHECK: no_retention=0 primary=0{{$}}
// CHECK: condition=rtc{{$}}
// CHECK: strategy=1 boundary=0{{$}}

// 1801-2018 10.6.1.2: set_retention makes this object. Its parent is the domain, its creation scope the
// domain's scope, and it owns the predefined handles retention_supply and primary_supply.
module leaf(input logic clk);
  logic state = 0;
  always @(posedge clk) state <= !state;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic clk = 0, rtc = 0;
leaf dut(clk);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = at("/top/PD.KEEP");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  $display("element=%s", link(upf_query_object_properties(h, UPF_EFFECTIVE_EXTENTS), UPF_HDL_ELEMENT));
  each("handle", upf_query_object_properties(h, UPF_SUPPLY_SET_HANDLES));
  $display("no_retention=%0d primary=%0d", number(h, UPF_IS_NO_RETENTION), number(h, UPF_IS_USE_RETENTION_AS_PRIMARY));
  $display("condition=%s", text(upf_query_object_properties(h, UPF_RETENTION_CONDITION), UPF_EXPR_STRING));
  $display("strategy=%0d boundary=%0d", upf_object_in_class(h, UPF_STRATEGY), upf_object_in_class(h, UPF_BOUNDARY_STRATEGY));
  $finish;
end
endmodule
