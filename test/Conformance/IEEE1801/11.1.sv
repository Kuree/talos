// CLAUSE: Tcl interface
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties, upf_query_object_type, upf_object_in_class, upf_query_object_pathname, query_upf (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=ISO{{$}}
// CHECK: kind=upfIsolationStrategyT{{$}}
// CHECK: member=1{{$}}
// CHECK: path=PD.ISO{{$}}
// CHECK: nets=VDD VSS{{$}}

// 1801-2018 11.1: the Tcl interface, one call of each of its five commands. The results become parameters
// of a checker, since phase 5 allows no command that changes the power intent itself (11.1.1).
module show #(parameter string name = "unset", kind = "unset", member = "unset", path = "unset", nets = "unset");
initial begin
  $display("name=%s", name);
  $display("kind=%s", kind);
  $display("member=%s", member);
  $display("path=%s", path);
  $display("nets=%s", nets);
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
