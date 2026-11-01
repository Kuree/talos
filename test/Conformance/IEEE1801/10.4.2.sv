// CLAUSE: UPF objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=UPF_POWER_DOMAIN PD line 5{{$}}
// CHECK: state=UPF_POWER_STATE ON line 4{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: effect=/top/dut{{$}}
// CHECK: group=1 1{{$}}

// 1801-2018 10.4.2: UPF objects are created by UPF commands, such as domains and power states, and hold
// both what the command said (file, line, name) and its effect on the HDL (the resolved extent).
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT domain, state;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  domain = upf_get_handle_by_name("/top/PD");
  state = upf_get_handle_by_name("/top/CORE.ON");
  $display("domain=%s %s line %0d", kind(domain), text(domain, UPF_NAME), number(domain, UPF_LINE));
  $display("state=%s %s line %0d", kind(state), text(state, UPF_NAME), number(state, UPF_LINE));
  $display("file=%s", text(domain, UPF_FILE));
  $display("effect=%s", link(upf_query_object_properties(domain, UPF_EFFECTIVE_EXTENTS), UPF_HDL_ELEMENT));
  $display("group=%0d %0d", upf_object_in_class(domain, UPF_BASE_UPF), upf_object_in_class(state, UPF_BASE_UPF));
  $finish;
end
endmodule
