// CLAUSE: Control sensitivity
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_SIGNAL_SENSE{{$}}
// CHECK: control=/top/ctrl{{$}}
// CHECK: sense=UPF_SENSE_LOW{{$}}

// 1801-2018 10.6.3.2 Table 30: set_isolation's -isolation_signal and -isolation_sense give the control
// signal and sensitivity. Low is used because it is not the default; balloon retention has no support yet.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic ctrl = 1;
upfSignalSenseKindE level;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_iter_get_next(upf_query_object_properties(at("/top/PD.ISO"), UPF_ISOLATION_CONTROLS));
  level = upfSignalSenseKindE'(number(h, UPF_SIGNAL_SENSITIVITY));
  $display("class=%s", kind(h));
  $display("control=%s", link(h, UPF_CONTROL_SIGNAL));
  $display("sense=%s", level.name());
  $finish;
end
endmodule
