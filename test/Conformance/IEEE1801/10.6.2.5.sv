// CLAUSE: HDL multibit net
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: net=UPF_HDL_NET_MULTI_BIT reg_arr /top/dut{{$}}
// CHECK: width=3{{$}}
// CHECK: bits=3 sum=3{{$}}
// CHECK: extent=/top/PD.ret{{$}}

// 1801-2018 10.6.2.5: a multi-bit net normalized as width-1 downto 0, with the values in its example table.
module leaf(input logic clk);
  logic [2:0] reg_arr = 0;
  always @(posedge clk) reg_arr <= reg_arr + 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic clk = 0, rtc = 0;
leaf dut(clk);
upfHandleT bits, b;
int count = 0, sum = 0;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/dut/reg_arr");
  $display("net=%s %s %s", kind(h), text(h, UPF_NAME), link(h, UPF_PARENT));
  $display("width=%0d", number(h, UPF_HDL_WIDTH));
  bits = upf_query_object_properties(h, UPF_NORMALIZED_BITS);
  for (b = upf_iter_get_next(bits); b != upf_null; b = upf_iter_get_next(bits)) begin
    count++;
    sum += number(b, UPF_NORMALIZED_IDX);
  end
  $display("bits=%0d sum=%0d", count, sum);
  $display("extent=%s", link(upf_iter_get_next(upf_query_object_properties(h, UPF_EXTENTS)), UPF_OBJECT));
  $finish;
end
endmodule
