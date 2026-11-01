// CLAUSE: Power state
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.14/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_STATE{{$}}
// CHECK: name=ON{{$}}
// CHECK: parent=/top/CORE{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}
// CHECK: scope=/top{{$}}
// CHECK: simstate=NORMAL illegal=0{{$}}
// CHECK: expr=power == FULL_ON && ground == FULL_ON{{$}}
// CHECK: before=0{{$}}
// CHECK: active=1{{$}}
// CHECK: after=0{{$}}

// 1801-2018 10.6.1.14: add_power_state makes this object; its parent is the object given the state, and
// the dynamic upf_is_active follows the state's defining expression.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
upfSimstateE sim;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/CORE.ON");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  sim = upfSimstateE'(number(h, UPF_SIMSTATE));
  $display("simstate=%s illegal=%0d", sim.name(), number(h, UPF_IS_ILLEGAL));
  $display("expr=%s", text(upf_query_object_properties(h, UPF_SUPPLY_EXPR), UPF_EXPR_STRING));
  $display("before=%0d", number(h, UPF_IS_ACTIVE));
  void'(supply_on("/top/VDD"));
  void'(supply_on("/top/VSS", 0.0));
  #1;
  $display("active=%0d", number(h, UPF_IS_ACTIVE));
  void'(supply_off("/top/VDD"));
  #1;
  $display("after=%0d", number(h, UPF_IS_ACTIVE));
  $finish;
end
endmodule
