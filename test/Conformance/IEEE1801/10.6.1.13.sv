// CLAUSE: Ack port
// REQUIRES: upf
// XFAIL: *
// create_power_switch rejects -ack_port and -ack_delay, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.13/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_ACK_PORT{{$}}
// CHECK: name=ts_ack{{$}}
// CHECK: parent=/top/PS{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=6{{$}}
// CHECK: scope=/top{{$}}
// CHECK: dir=UPF_DIR_OUT{{$}}
// CHECK: delay=100ns{{$}}
// CHECK: hiconn=/top/ack{{$}}
// CHECK: start=0{{$}}
// CHECK: on=1 ack=1{{$}}

// 1801-2018 10.6.1.13: -ack_port makes this always-output object. 6.22: the default expression is the
// constant 1, driven delay after turn-on, with the inverse as the initial value.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic en = 0;
wire ack;
upfPortDirE dir;
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
  h = at("/top/PS/ts_ack");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  dir = upfPortDirE'(number(h, UPF_PORT_DIR));
  $display("dir=%s", dir.name());
  $display("delay=%s", text(h, UPF_ACK_DELAY));
  each("hiconn", upf_query_object_properties(h, UPF_HICONN));
  $display("start=%0d", number(h, UPF_CURRENT_VALUE));
  void'(supply_on("/top/VDD"));
  void'(supply_on("/top/VSS", 0.0));
  en = 1;
  #200ns;
  $display("on=%0d ack=%b", number(h, UPF_CURRENT_VALUE), ack);
  $finish;
end
endmodule
