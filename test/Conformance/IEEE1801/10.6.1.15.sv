// CLAUSE: Power switch state
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.15/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_SWITCH_STATE{{$}}
// CHECK: name=ss_on{{$}}
// CHECK: parent=/top/PS{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=6{{$}}
// CHECK: scope=/top{{$}}
// CHECK: on=FULL_ON ss_ctrl{{$}}
// CHECK: input=/top/PS/vin{{$}}
// CHECK: off=OFF !ss_ctrl{{$}}

// 1801-2018 10.6.1.15: each switch state option makes this object, which records its expression, its
// input port and the output state while active. ON and OFF states must differ in each.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic en = 0;
upfSupplyStateE output_state;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/PS.ss_on");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  output_state = upfSupplyStateE'(number(h, UPF_SWITCH_OUTPUT_STATE));
  $display("on=%s %s", output_state.name(), text(upf_query_object_properties(h, UPF_SWITCH_EXPR), UPF_EXPR_STRING));
  $display("input=%s", link(h, UPF_INPUT_SUPPLY_PORT));
  h = at("/top/PS.ss_off");
  output_state = upfSupplyStateE'(number(h, UPF_SWITCH_OUTPUT_STATE));
  $display("off=%s %s", output_state.name(), text(upf_query_object_properties(h, UPF_SWITCH_EXPR), UPF_EXPR_STRING));
  $finish;
end
endmodule
