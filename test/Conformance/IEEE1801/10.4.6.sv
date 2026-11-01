// CLAUSE: Class hierarchy
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: isolation=1 1 1 1 1 1{{$}}
// CHECK: retention=1 1 1 1 1 0{{$}}
// CHECK: domain=1 1 1 1 0 0{{$}}
// CHECK: net=1 1 1 0 0 0{{$}}

// 1801-2018 10.4.6, class memberships in 10.6.1: each class is in all its ancestors and in no sibling.
// Isolation is a boundary strategy, retention only a strategy, a domain has extents, a net has neither.
module leaf(input logic clk, output logic q);
  logic state = 0;
  always @(posedge clk) state <= !state;
  assign q = state;
endmodule
module top;
import UPF::*;
logic clk = 0, iso = 0, rtc = 0;
wire q;
leaf dut(clk, q);
function automatic void chain(string key, upfHandleT o);
  $display("%s=%0d %0d %0d %0d %0d %0d", key, upf_object_in_class(o, UPF_BASE), upf_object_in_class(o, UPF_BASE_NAMED),
           upf_object_in_class(o, UPF_BASE_UPF), upf_object_in_class(o, UPF_EXTENT_CLASS),
           upf_object_in_class(o, UPF_STRATEGY), upf_object_in_class(o, UPF_BOUNDARY_STRATEGY));
endfunction
initial begin
  chain("isolation", upf_get_handle_by_name("/top/PD.ISO"));
  chain("retention", upf_get_handle_by_name("/top/PD.KEEP"));
  chain("domain", upf_get_handle_by_name("/top/PD"));
  chain("net", upf_get_handle_by_name("/top/VDD"));
  $finish;
end
endmodule
