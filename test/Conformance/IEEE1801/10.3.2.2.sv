// CLAUSE: Hierarchical path ID
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=/top/PD 1{{$}}
// CHECK: strategy=/top/PD.ISO 1{{$}}
// CHECK: bit=UPF_HDL_PORT_BIT{{$}}

// 1801-2018 10.3.2.2.1, 10.6.1.1, 10.6.1.3: a path ID joins names with '/', '.' and '@'. A domain ID is
// <parent>/<name> and a strategy ID is <parent>.<name>; each rebuilt ID must find the object again.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
logic iso = 0;
upfHandleT domain, strategy, bit0;
string id;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  domain = upf_get_handle_by_name("/top/PD");
  strategy = upf_get_handle_by_name("/top/PD.ISO");
  id = {link(domain, UPF_PARENT), "/", text(domain, UPF_NAME)};
  $display("domain=%s %0d", id, upf_get_handle_by_name(id) == domain);
  id = {link(strategy, UPF_PARENT), ".", text(strategy, UPF_NAME)};
  $display("strategy=%s %0d", id, upf_get_handle_by_name(id) == strategy);
  bit0 = upf_get_handle_by_name("/top/dut/q@0");
  $display("bit=%s", kind(bit0));
  $finish;
end
endmodule
