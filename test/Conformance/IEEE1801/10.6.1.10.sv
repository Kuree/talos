// CLAUSE: Logic net
// REQUIRES: upf
// XFAIL: *
// create_logic_net is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.10/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_LOGIC_NET{{$}}
// CHECK: name=sig{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=1{{$}}
// CHECK: scope=/top{{$}}
// CHECK: write=1{{$}}
// CHECK: first=1{{$}}
// CHECK: second=0{{$}}

// 1801-2018 10.6.1.10: create_logic_net makes this object. 11.2.3.3.1: a net with no driver accepts
// writes to its dynamic current value, which holds until the next write.
module top;
import UPF::*;
upfHandleT h;
upfHandleT value;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/sig");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  value = upf_query_object_properties(h, UPF_CURRENT_VALUE);
  $display("write=%0d", upf_set_value_int(value, 1));
  $display("first=%0d", number(h, UPF_CURRENT_VALUE));
  void'(upf_set_value_int(value, 0));
  $display("second=%0d", number(h, UPF_CURRENT_VALUE));
  $finish;
end
endmodule
