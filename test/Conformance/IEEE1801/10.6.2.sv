// CLAUSE: HDL objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: scope=UPF_HDL_SCOPE{{$}}
// CHECK: portbit=UPF_HDL_PORT_BIT{{$}}
// CHECK: portbits=UPF_HDL_PORT_MULTI_BIT{{$}}
// CHECK: netbit=UPF_HDL_NET_BIT{{$}}
// CHECK: netbits=UPF_HDL_NET_MULTI_BIT{{$}}
// CHECK: slice=UPF_HDL_MULTI_BIT_SLICE{{$}}

// 1801-2018 10.6.2: each kind of HDL object has its class once it takes part in the power intent.
module leaf(input logic clk, output logic port1, output logic [2:0] port2);
  logic [2:0] state = 0;
  always @(posedge clk) state <= state + 1;
  assign port1 = 1;
  assign port2 = state;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic clk = 0, iso = 0, rtc = 0;
wire port1;
wire [2:0] port2;
leaf dut(clk, port1, port2);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("scope=%s", kind(at("/top/dut")));
  $display("portbit=%s", kind(at("/top/dut/port1")));
  $display("portbits=%s", kind(at("/top/dut/port2")));
  $display("netbit=%s", kind(at("/top/iso")));
  $display("netbits=%s", kind(at("/top/dut/state")));
  $display("slice=%s", kind(at("/top/dut/state@1:0")));
  $finish;
end
endmodule
