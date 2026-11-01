// CLAUSE: upf_query_object_pathname
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.5.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: absolute=/top/dut/PD{{$}}
// CHECK: relative=dut/PD{{$}}
// CHECK: strategy=dut/PD.ISO{{$}}
// CHECK: rtl=/top/dut/mid/q[1]{{$}}

// 1801-2018 11.2.3.5.3: the absolute name, the relative one from its example, and the RTL name of an HDL object.
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
initial begin
  pd = upf_get_handle_by_name("/top/dut/PD");
  top_scope = upf_get_handle_by_name("/top");
  $display("absolute=%s", upf_query_object_pathname(pd));
  $display("relative=%s", upf_query_object_pathname(pd, top_scope));
  $display("strategy=%s", upf_query_object_pathname(upf_get_handle_by_name("/top/dut/PD.ISO"), top_scope));
  $display("rtl=%s", upf_query_object_pathname(upf_get_handle_by_name("/top/dut/mid/q@1")));
  $finish;
end
endmodule
