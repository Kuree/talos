// CLAUSE: Isolation strategy
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_ISOLATION_STRATEGY{{$}}
// CHECK: name=ISO{{$}}
// CHECK: parent=/top/PD{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}
// CHECK: scope=/top{{$}}
// CHECK: element=/top/dut/q{{$}}
// CHECK: location=PARENT applies=UPF_FILTER_OUTPUTS{{$}}
// CHECK: ref=/top/PD.ISO.isolation_signal{{$}}
// CHECK: control=/top/iso UPF_SENSE_LOW{{$}}
// CHECK: boundary=1{{$}}

// 1801-2018 10.6.1.3: set_isolation makes this object. The non-default sense, location and applies_to
// must come from the command, and the control is reached through its upfSignalSenseT object.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 1;
upfLocationE where;
upfAppliesToFilterE applies;
upfHandleT sense;
upfSignalSenseKindE level;
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
  h = at("/top/PD.ISO");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  $display("element=%s", link(upf_query_object_properties(h, UPF_EFFECTIVE_EXTENTS), UPF_HDL_ELEMENT));
  where = upfLocationE'(number(h, UPF_LOCATION));
  applies = upfAppliesToFilterE'(number(h, UPF_APPLIES_TO));
  $display("location=%s applies=%s", where.name(), applies.name());
  each("ref", upf_query_object_properties(h, UPF_LOGIC_REFS));
  sense = upf_iter_get_next(upf_query_object_properties(h, UPF_ISOLATION_CONTROLS));
  level = upfSignalSenseKindE'(number(sense, UPF_SIGNAL_SENSITIVITY));
  $display("control=%s %s", link(sense, UPF_CONTROL_SIGNAL), level.name());
  $display("boundary=%0d", upf_object_in_class(h, UPF_BOUNDARY_STRATEGY));
  $finish;
end
endmodule
