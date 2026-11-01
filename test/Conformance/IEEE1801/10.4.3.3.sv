// CLAUSE: Complex HDL objects
// REQUIRES: upf
// XFAIL: *
// A packed struct in a domain is rejected (initial UPF corruption supports packed integral state), and the UPF package has no information-model API.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: whole=UPF_HDL_NET_MULTI_BIT 5{{$}}
// CHECK: a=UPF_HDL_MULTI_BIT_SLICE 2{{$}}
// CHECK: b=UPF_HDL_MULTI_BIT_SLICE 3{{$}}
// CHECK: path=/top/dut/state.a{{$}}

// 1801-2018 10.4.3.3: a complex signal is a multi-bit object over a normalized bit vector. The normalization
// is the tool's, so only invariants are compared: total width, each field's slice width, its RTL name.
typedef struct packed {logic [1:0] a; logic [2:0] b;} pair_t;
module leaf(input logic clk, input pair_t d);
  pair_t state;
  always @(posedge clk) state <= d;
endmodule
module top;
import UPF::*;
logic clk = 0, rtc = 0;
pair_t d = 0;
leaf dut(clk, d);
upfHandleT whole, a, b;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
initial begin
  whole = upf_get_handle_by_name("/top/dut/state");
  a = upf_get_handle_by_name("/top/dut/state.a");
  b = upf_get_handle_by_name("/top/dut/state.b");
  $display("whole=%s %0d", kind(whole), number(whole, UPF_HDL_WIDTH));
  $display("a=%s %0d", kind(a), number(a, UPF_MSB) - number(a, UPF_LSB) + 1);
  $display("b=%s %0d", kind(b), number(b, UPF_MSB) - number(b, UPF_LSB) + 1);
  $display("path=%s", upf_query_object_pathname(a));
  $finish;
end
endmodule
