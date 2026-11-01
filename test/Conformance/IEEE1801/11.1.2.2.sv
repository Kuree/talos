// CLAUSE: upf_query_object_type
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties, upf_query_object_type (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: upf=upfPowerDomainT{{$}}
// CHECK: hdl=upfHdlScopeT{{$}}
// CHECK: relationship=upfExtentT{{$}}

// 1801-2018 11.1.2.2: the query returns the class keyword, with one example for each of the three object groups.
module show #(parameter string upf = "unset", hdl = "unset", relationship = "unset");
initial begin
  $display("upf=%s", upf);
  $display("hdl=%s", hdl);
  $display("relationship=%s", relationship);
end
endmodule
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
logic iso = 0;
wire q;
leaf dut(q);
endmodule
