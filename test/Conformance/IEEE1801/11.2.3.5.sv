// CLAUSE: Utility functions
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: type=UPF_POWER_DOMAIN{{$}}
// CHECK: class=1 0{{$}}
// CHECK: path=dut/PD{{$}}

// 1801-2018 11.2.3.5: the type, class-membership and pathname utilities on one domain.
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
upfHandleT pd, top_scope;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  pd = upf_get_handle_by_name("/top/dut/PD");
  top_scope = upf_get_handle_by_name("/top");
  $display("type=%s", kind(pd));
  $display("class=%0d %0d", upf_object_in_class(pd, UPF_EXTENT_CLASS), upf_object_in_class(pd, UPF_STRATEGY));
  $display("path=%s", upf_query_object_pathname(pd, top_scope));
  $finish;
end
endmodule
