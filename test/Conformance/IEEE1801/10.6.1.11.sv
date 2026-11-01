// CLAUSE: Logic port
// REQUIRES: upf
// XFAIL: *
// create_logic_port is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.11/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_LOGIC_PORT{{$}}
// CHECK: name=iso_ctrl{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=1{{$}}
// CHECK: scope=/top{{$}}
// CHECK: dir=UPF_DIR_IN{{$}}
// CHECK: value=1{{$}}
// CHECK: control=UPF_LOGIC_PORT{{$}}

// 1801-2018 10.6.1.11: create_logic_port and a power switch's control ports make this object. As a
// root driver the port accepts a write (11.2.3.3.1).
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic en = 0;
upfPortDirE dir;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/iso_ctrl");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  dir = upfPortDirE'(number(h, UPF_PORT_DIR));
  $display("dir=%s", dir.name());
  void'(upf_set_value_int(upf_query_object_properties(h, UPF_CURRENT_VALUE), 1));
  $display("value=%0d", number(h, UPF_CURRENT_VALUE));
  $display("control=%s", kind(at("/top/PS/en")));
  $finish;
end
endmodule
