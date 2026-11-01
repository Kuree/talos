// CLAUSE: Multi-bit representation of complex HDL objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: width=8{{$}}
// CHECK: bit=UPF_HDL_NET_BIT 3 1{{$}}
// CHECK: rtl=/top/dut/sig[3]{{$}}
// CHECK: slice=UPF_HDL_MULTI_BIT_SLICE 7 6{{$}}
// CHECK: slicebits=2{{$}}

// 1801-2018 10.4.3.3.2 and Table 14: a [7:0] object has width 8, a bit has both the RTL handle sig[3]
// and the normalized sig@3, the API recovers the RTL name, and sig@7:6 is a two-bit slice.
module leaf(input logic clk, input logic [7:0] d);
  logic [7:0] sig;
  always @(posedge clk) sig <= d;
endmodule
module top;
import UPF::*;
logic clk = 0, rtc = 0;
logic [7:0] d = 0;
leaf dut(clk, d);
upfHandleT rtl, normalized, slice, bits;
int count = 0;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
initial begin
  rtl = upf_get_handle_by_name("/top/dut/sig[3]");
  normalized = upf_get_handle_by_name("/top/dut/sig@3");
  $display("width=%0d", number(upf_get_handle_by_name("/top/dut/sig"), UPF_HDL_WIDTH));
  $display("bit=%s %0d %0d", kind(normalized), number(normalized, UPF_NORMALIZED_IDX), rtl == normalized);
  $display("rtl=%s", upf_query_object_pathname(normalized));
  slice = upf_get_handle_by_name("/top/dut/sig@7:6");
  $display("slice=%s %0d %0d", kind(slice), number(slice, UPF_MSB), number(slice, UPF_LSB));
  bits = upf_query_object_properties(slice, UPF_SLICE_BITS);
  while (upf_iter_get_next(bits) != upf_null) count++;
  $display("slicebits=%0d", count);
  $finish;
end
endmodule
