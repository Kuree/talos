// CLAUSE: Supply set
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_SUPPLY_SET{{$}}
// CHECK: name=SS1{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=3{{$}}
// CHECK: scope=/top{{$}}
// CHECK-DAG: function=/top/SS1.power{{$}}
// CHECK-DAG: function=/top/SS1.ground{{$}}
// CHECK-DAG: equivalent=/top/SS1{{$}}
// CHECK-DAG: equivalent=/top/PD.primary{{$}}
// CHECK: local=UPF_SUPPLY_SET /top/PD{{$}}
// CHECK: sim=NORMAL{{$}}

// 1801-2018 10.6.1.6: a global set's parent is its HDL scope and a local set's the UPF object holding the
// handle. The association in the example makes each equivalent to the other.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
upfHandleT local_set;
upfSimstateE sim;
wire q;
leaf dut(q);
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
  h = at("/top/SS1");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  each("function", upf_query_object_properties(h, UPF_FUNCTIONS));
  each("equivalent", upf_query_object_properties(h, UPF_EQUIVALENT_SETS));
  local_set = at("/top/PD.primary");
  $display("local=%s %s", kind(local_set), link(local_set, UPF_PARENT));
  void'(supply_on("/top/VDD"));
  void'(supply_on("/top/VSS", 0.0));
  #1;
  sim = upfSimstateE'(number(local_set, UPF_CURRENT_SIMSTATE));
  $display("sim=%s", sim.name());
  $finish;
end
endmodule
