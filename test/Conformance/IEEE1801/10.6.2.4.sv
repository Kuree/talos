// CLAUSE: HDL scalar net
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: net=UPF_HDL_NET_BIT ctrl /top{{$}}
// CHECK: same=1{{$}}

// 1801-2018 10.6.2.4: a scalar net that took part in the intent, here as in its example, an isolation
// signal. The strategy's control and the name lookup must be one object (11.2.2.1 NOTE 2).
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic ctrl = 0;
upfHandleT sense;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/ctrl");
  $display("net=%s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT));
  sense = upf_iter_get_next(upf_query_object_properties(at("/top/PD.ISO"), UPF_ISOLATION_CONTROLS));
  $display("same=%0d", upf_query_object_properties(sense, UPF_CONTROL_SIGNAL) == h);
  $finish;
end
endmodule
