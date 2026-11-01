// CLAUSE: Tool-generated ID
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties, upf_query_object_type (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: extent=#UPFEXTENT{{[0-9]*}}#{{$}}
// CHECK: kind=upfExtentT{{$}}
// CHECK: element=/top/dut{{$}}
// CHECK: designClass=upfDesignT{{$}}

// 1801-2018 10.3.2.3: a tool-generated ID has a mandatory # prefix and suffix and may carry a counter,
// and it is a working handle for further queries. 10.6.3.6 fixes the design object's ID.
module show #(parameter string extent = "unset", kind = "unset", element = "unset", designClass = "unset");
initial begin
  $display("extent=%s", extent);
  $display("kind=%s", kind);
  $display("element=%s", element);
  $display("designClass=%s", designClass);
end
endmodule
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
wire q;
leaf dut(q);
endmodule
