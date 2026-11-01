// CLAUSE: Power state group
// REQUIRES: upf
// XFAIL: *
// create_power_state_group is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.21/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_STATE_GROUP{{$}}
// CHECK: name=CPU_cluster{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}
// CHECK: scope=/top{{$}}
// CHECK: state=/top/CPU_cluster.RUN1{{$}}
// CHECK: member=UPF_POWER_STATE{{$}}

// 1801-2018 10.6.1.21: create_power_state_group makes this object and add_power_state -group adds states
// to it. Its table says upf_pst_states; the class's property list and Table 40 say upf_group_states.
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
  h = at("/top/CPU_cluster");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  each("state", upf_query_object_properties(h, UPF_GROUP_STATES));
  $display("member=%s", kind(at("/top/CPU_cluster.RUN1")));
  $finish;
end
endmodule
