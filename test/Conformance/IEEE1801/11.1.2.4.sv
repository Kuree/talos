// CLAUSE: upf_query_object_pathname
// REQUIRES: upf
// XFAIL: *
// upf_query_object_pathname (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: absolute=/top/dut/PD.ISO{{$}}
// CHECK: relative=dut/PD.ISO{{$}}
// CHECK: notAncestor={{$}}
// CHECK: relationship={{$}}
// CHECK: rtl=/top/dut/mid/q[1]{{$}}

// 1801-2018 11.1.2.4: an absolute name by default, a relative one from an ancestor, an empty string from a
// non-ancestor or for a relationship object, and the RTL name of a normalized bit.
module show #(parameter string absolute = "unset", relative = "unset", notAncestor = "unset", relationship = "unset", rtl = "unset");
initial begin
  $display("absolute=%s", absolute);
  $display("relative=%s", relative);
  $display("notAncestor=%s", notAncestor);
  $display("relationship=%s", relationship);
  $display("rtl=%s", rtl);
end
endmodule
module inner(output logic [1:0] q);
  assign q = 2'b01;
endmodule
module leaf(output wire [1:0] q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
wire [1:0] q;
leaf dut(q);
endmodule
