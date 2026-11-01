// CLAUSE: Named object reference
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_NAMED_REF{{$}}
// CHECK: name=power{{$}}
// CHECK: parent=/top/SS1{{$}}
// CHECK: power=UPF_REF_POWER /top/VDD{{$}}
// CHECK: ground=UPF_REF_GROUND /top/VSS{{$}}
// CHECK: signal=UPF_REF_ISO_SIGNAL /top/iso{{$}}

// 1801-2018 10.6.1.7: named references stand for supply set functions and strategy logic refs, and
// upf_ref_object reaches the original object. Each kind must point at its own target.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
upfNamedRefKindE ref_kind;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/SS1.power");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  ref_kind = upfNamedRefKindE'(number(h, UPF_REF_KIND));
  $display("power=%s %s", ref_kind.name(), link(h, UPF_REF_OBJECT));
  h = at("/top/SS1.ground");
  ref_kind = upfNamedRefKindE'(number(h, UPF_REF_KIND));
  $display("ground=%s %s", ref_kind.name(), link(h, UPF_REF_OBJECT));
  h = at("/top/PD.ISO.isolation_signal");
  ref_kind = upfNamedRefKindE'(number(h, UPF_REF_KIND));
  $display("signal=%s %s", ref_kind.name(), link(h, UPF_REF_OBJECT));
  $finish;
end
endmodule
