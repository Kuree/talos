// CLAUSE: Absolute information-model paths
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: scope=UPF_HDL_SCOPE /top/dut/mid{{$}}
// CHECK: strategy=UPF_ISOLATION_STRATEGY /top/dut/PD.ISO{{$}}
// CHECK: bit=UPF_HDL_PORT_BIT /top/dut/mid/q[1]{{$}}

// 1801-2018 10.3.2.2.1: a path ID is absolute from the UPF root whatever scope created the object. The
// clause's three examples: a scope, a strategy, and a bit (whose RTL name comes from 10.4.3.3.2 NOTE 1).
module inner(output logic [1:0] q);
  assign q = 2'b01;
endmodule
module leaf(output wire [1:0] q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
import UPF::*;
wire [1:0] q;
leaf dut(q);
upfHandleT h;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  h = upf_get_handle_by_name("/top/dut/mid");
  $display("scope=%s %s", kind(h), upf_query_object_pathname(h));
  h = upf_get_handle_by_name("/top/dut/PD.ISO");
  $display("strategy=%s %s", kind(h), upf_query_object_pathname(h));
  h = upf_get_handle_by_name("/top/dut/mid/q@1");
  $display("bit=%s %s", kind(h), upf_query_object_pathname(h));
  $finish;
end
endmodule
