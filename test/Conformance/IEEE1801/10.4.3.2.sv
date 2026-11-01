// CLAUSE: UPF information model and other HDL information models
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties, upf_query_object_pathname (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: rtl=/top/dut{{$}}
// CHECK: relative=dut{{$}}
// CHECK: nets=dut/n1 dut/n2{{$}}

// 1801-2018 10.4.3.2: the model only abstracts the HDL, so more detail comes from find_objects using the
// RTL pathname the API provides. The nets are not otherwise in the model. 6.31.1 bars an absolute scope.
module show #(parameter string rtl = "unset", relative = "unset", nets = "unset");
initial begin
  $display("rtl=%s", rtl);
  $display("relative=%s", relative);
  $display("nets=%s", nets);
end
endmodule
module inner(output logic q);
  assign q = 1;
endmodule
module leaf(output wire q);
  wire n1, n2;
  inner mid(q);
endmodule
module top;
wire q;
leaf dut(q);
endmodule
