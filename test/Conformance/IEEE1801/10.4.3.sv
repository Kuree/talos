// CLAUSE: HDL objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: scope=UPF_HDL_SCOPE{{$}}
// CHECK: port=UPF_HDL_PORT_BIT{{$}}
// CHECK: ports=UPF_HDL_PORT_MULTI_BIT{{$}}
// CHECK: net=UPF_HDL_NET_BIT{{$}}
// CHECK: hdl=1{{$}}

// 1801-2018 10.4.3.1: HDL objects abstract the design in language-independent classes. Instances, scalar
// and multi-bit ports and a control net that took part in the intent each have their own class (10.6.2).
module leaf(output logic p, output logic [2:0] q);
  assign p = 1;
  assign q = 3'b101;
endmodule
module top;
import UPF::*;
logic iso = 0;
wire p;
wire [2:0] q;
leaf dut(p, q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("scope=%s", kind(upf_get_handle_by_name("/top/dut")));
  $display("port=%s", kind(upf_get_handle_by_name("/top/dut/p")));
  $display("ports=%s", kind(upf_get_handle_by_name("/top/dut/q")));
  $display("net=%s", kind(upf_get_handle_by_name("/top/iso")));
  $display("hdl=%0d", upf_object_in_class(upf_get_handle_by_name("/top/iso"), UPF_BASE_HDL));
  $finish;
end
endmodule
