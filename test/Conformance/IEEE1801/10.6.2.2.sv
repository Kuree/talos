// CLAUSE: HDL scalar port
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: scalar=UPF_HDL_PORT_BIT port1 /top/dut UPF_DIR_OUT{{$}}
// CHECK: extent=/top/PD.ISO{{$}}
// CHECK: bit=UPF_HDL_PORT_BIT [2] /top/dut/port2 2{{$}}

// 1801-2018 10.6.2.2: a scalar port or one bit of a multi-bit port, with the values in its example tables.
module leaf(output logic port1, output logic [2:0] port2);
  assign port1 = 1;
  assign port2 = 3'b101;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
wire port1;
wire [2:0] port2;
leaf dut(port1, port2);
upfPortDirE dir;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/dut/port1");
  dir = upfPortDirE'(number(h, UPF_PORT_DIR));
  $display("scalar=%s %s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT), dir.name());
  $display("extent=%s", link(upf_iter_get_next(upf_query_object_properties(h, UPF_EXTENTS)), UPF_OBJECT));
  h = at("/top/dut/port2[2]");
  $display("bit=%s %s %s %0d", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT), number(h, UPF_NORMALIZED_IDX));
  $finish;
end
endmodule
