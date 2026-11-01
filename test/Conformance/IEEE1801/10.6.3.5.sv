// CLAUSE: UPF attributes
// REQUIRES: upf
// XFAIL: *
// set_port_attributes is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_ATTRIBUTE{{$}}
// CHECK: attr=UPF_clamp_value 1{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}

// 1801-2018 10.6.3.5: set_port_attributes makes this object, with the values in its example table.
module leaf(output wire my_Logic_Port);
  assign my_Logic_Port = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire my_Logic_Port;
leaf dut(my_Logic_Port);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_iter_get_next(upf_query_object_properties(at("/top/dut/my_Logic_Port"), UPF_HDL_ATTRIBUTES));
  $display("class=%s", kind(h));
  $display("attr=%s %s", text(h, UPF_ATTR_NAME), text(h, UPF_ATTR_VALUE));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $finish;
end
endmodule
