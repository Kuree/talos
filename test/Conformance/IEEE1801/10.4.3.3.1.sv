// CLAUSE: Complex HDL signals as bit vectors
// REQUIRES: upf
// XFAIL: *
// A packed struct in a domain is rejected (initial UPF corruption supports packed integral state), and the UPF package has no information-model API.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_HDL_NET_MULTI_BIT{{$}}
// CHECK: width=5{{$}}
// CHECK: bits=5 sum=10{{$}}

// 1801-2018 10.4.3.3.1: a struct becomes a normalized vector of bits. Its 5 bits must carry the
// indices 0 to 4 (10.6.2.5: width-1 downto 0), in whatever order the iterator returns them.
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
upfHandleT h, bits, b;
int count = 0, sum = 0;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_get_handle_by_name("/top/dut/state");
  $display("class=%s", kind(h));
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
