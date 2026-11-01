// CLAUSE: Power domain
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_DOMAIN{{$}}
// CHECK: name=PD{{$}}
// CHECK: parent=/top/dut{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}
// CHECK: scope=/top/dut{{$}}
// CHECK: element=/top/dut/mid{{$}}
// CHECK: handle=/top/dut/PD.primary{{$}}
// CHECK: upper=/top/dut/mid{{$}}
// CHECK: iso=/top/dut/PD.ISO{{$}}
// CHECK: extentclass=1 strategy=0{{$}}
// CHECK: on=NORMAL{{$}}
// CHECK: off=CORRUPT{{$}}

// 1801-2018 10.6.1.1: create_power_domain makes this object, with the values in its example table,
// and its dynamic simstate follows the primary supply.
module inner(output logic q);
  assign q = 1;
endmodule
module leaf(output wire q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
import UPF::*;
upfHandleT h;
wire q;
leaf dut(q);
upfSimstateE sim;
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
  h = at("/top/dut/PD");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  $display("element=%s", link(upf_query_object_properties(h, UPF_EFFECTIVE_EXTENTS), UPF_HDL_ELEMENT));
  each("handle", upf_query_object_properties(h, UPF_SUPPLY_SET_HANDLES));
  each("upper", upf_query_object_properties(h, UPF_UPPER_BOUNDARY));
  each("iso", upf_query_object_properties(h, UPF_ISOLATION_STRATEGIES));
  $display("extentclass=%0d strategy=%0d", upf_object_in_class(h, UPF_EXTENT_CLASS), upf_object_in_class(h, UPF_STRATEGY));
  void'(supply_on("/top/dut/VDD"));
  void'(supply_on("/top/dut/VSS", 0.0));
  #1;
  sim = upfSimstateE'(number(h, UPF_CURRENT_SIMSTATE));
  $display("on=%s", sim.name());
  void'(supply_off("/top/dut/VDD"));
  #1;
  sim = upfSimstateE'(number(h, UPF_CURRENT_SIMSTATE));
  $display("off=%s", sim.name());
  $finish;
end
endmodule
