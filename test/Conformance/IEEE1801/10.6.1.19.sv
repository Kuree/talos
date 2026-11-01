// CLAUSE: Power state transition
// REQUIRES: upf
// XFAIL: *
// add_state_transition is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.19/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_STATE_TRANSITION{{$}}
// CHECK: name=turn_on{{$}}
// CHECK: parent=/top/CORE{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=6{{$}}
// CHECK: scope=/top{{$}}
// CHECK: illegal=1 state=1{{$}}
// CHECK: from=/top/CORE.SLEEP{{$}}
// CHECK: to=/top/CORE.FAST{{$}}

// 1801-2018 10.6.1.19: add_state_transition makes this object, with the values in its example table.
// A supply set is used since domain states with -logic_expr have no support of their own yet.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
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
  h = at("/top/CORE.turn_on");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  $display("illegal=%0d state=%0d", number(h, UPF_IS_ILLEGAL), upf_object_in_class(h, UPF_STATE_CLASS));
  each("from", upf_query_object_properties(h, UPF_FROM_STATES));
  each("to", upf_query_object_properties(h, UPF_TO_STATES));
  $finish;
end
endmodule
