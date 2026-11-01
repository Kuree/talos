// CLAUSE: HDL multi-bit port
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: port=UPF_HDL_PORT_MULTI_BIT port2 /top/dut UPF_DIR_OUT{{$}}
// CHECK: width=3{{$}}
// CHECK: bits=3 sum=3{{$}}

// 1801-2018 10.6.2.3: a multi-bit port normalized as width-1 downto 0, with the values in its table.
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
upfHandleT bits, b;
int count = 0, sum = 0;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/dut/port2");
  dir = upfPortDirE'(number(h, UPF_PORT_DIR));
  $display("port=%s %s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT), dir.name());
  $display("width=%0d", number(h, UPF_HDL_WIDTH));
  bits = upf_query_object_properties(h, UPF_NORMALIZED_BITS);
  for (b = upf_iter_get_next(bits); b != upf_null; b = upf_iter_get_next(bits)) begin
    count++;
    sum += number(b, UPF_NORMALIZED_IDX);
  end
  $display("bits=%0d sum=%0d", count, sum);
  $finish;
end
endmodule
