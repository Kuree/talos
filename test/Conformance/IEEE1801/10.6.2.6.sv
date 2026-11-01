// CLAUSE: HDL multi-bit slice
// REQUIRES: upf
// XFAIL: *
// A packed struct in a domain is rejected (initial UPF corruption supports packed integral state), and the UPF package has no information-model API.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: slice=UPF_HDL_MULTI_BIT_SLICE @3:2 /top/dut/complex_rec{{$}}
// CHECK: msb=3 lsb=2{{$}}
// CHECK: bits=2{{$}}
// CHECK: field=UPF_HDL_MULTI_BIT_SLICE 3{{$}}

// 1801-2018 10.6.2.6: consecutive bits of a multi-bit object, with msb above lsb, as in its example
// table. A record field is also a slice; normalization is the tool's, so only its width is fixed.
module leaf(input logic clk);
  struct packed {logic [2:0] f1; logic f2;} complex_rec = 0;
  always @(posedge clk) complex_rec <= complex_rec + 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic clk = 0, rtc = 0;
leaf dut(clk);
upfHandleT bits;
int count = 0;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/dut/complex_rec@3:2");
  $display("slice=%s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT));
  $display("msb=%0d lsb=%0d", number(h, UPF_MSB), number(h, UPF_LSB));
  bits = upf_query_object_properties(h, UPF_SLICE_BITS);
  while (upf_iter_get_next(bits) != upf_null) count++;
  $display("bits=%0d", count);
  h = at("/top/dut/complex_rec.f1");
  $display("field=%s %0d", kind(h), number(h, UPF_MSB) - number(h, UPF_LSB) + 1);
  $finish;
end
endmodule
