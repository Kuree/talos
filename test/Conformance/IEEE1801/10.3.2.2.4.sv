// CLAUSE: Hierarchical path IDs and relative pathnames
// REQUIRES: upf
// XFAIL: *
// upf_query_object_pathname, upf_query_object_type (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: relative=/top/dut/PD{{$}}
// CHECK: dot=/top/dut{{$}}
// CHECK: tool=upfExtentT{{$}}
// CHECK: hdl=/top/dut/PD.primary{{$}}

// 1801-2018 10.3.2.2.4: a query prefixes a relative name with the active scope, and "." is that scope, but a
// tool-assigned ID stays unprefixed. 11.2.3.1.1: upf_get_handle_by_name builds an ID from relative_to.
module show #(parameter string relative = "unset", dot = "unset", tool = "unset");
import UPF::*;
upfHandleT scope;
initial begin
  $display("relative=%s", relative);
  $display("dot=%s", dot);
  $display("tool=%s", tool);
  scope = upf_get_handle_by_name("/top/dut");
  $display("hdl=%s", upf_query_object_pathname(upf_get_handle_by_name("PD.primary", scope)));
end
endmodule
module inner(output logic q);
  assign q = 1;
endmodule
module leaf(output wire q);
  inner mid(q);
endmodule
module top;
wire q;
leaf dut(q);
endmodule
