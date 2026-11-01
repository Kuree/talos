// CLAUSE: Object definitions
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: upf=UPF_ISOLATION_STRATEGY ISO /top/PD{{$}}
// CHECK: hdl=UPF_HDL_SCOPE dut /top{{$}}
// CHECK: relationship=UPF_EXPRESSION power == FULL_ON && ground == FULL_ON{{$}}

// 1801-2018 10.6: a definition gives each class its handle form and properties. One object per group,
// read through the properties its own definition lists.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/PD.ISO");
  $display("upf=%s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT));
  h = at("/top/dut");
  $display("hdl=%s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT));
  h = upf_query_object_properties(at("/top/CORE.ON"), UPF_SUPPLY_EXPR);
  $display("relationship=%s %s", kind(h), text(h, UPF_EXPR_STRING));
  $finish;
end
endmodule
