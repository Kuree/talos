// CLAUSE: upf_query_object_properties
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=ISO{{$}}
// CHECK: line=4{{$}}
// CHECK: functions=2{{$}}
// CHECK: parent=/top{{$}}
// CHECK: badProperty=1{{$}}
// CHECK: wrongClass=1{{$}}
// CHECK: badHandle=1{{$}}

// 1801-2018 11.1.2.1: -property returns one value, a list property is a Tcl list, no -property returns every
// key and value, and a bad property, a property of another class or an absent object is an error.
module show #(parameter string name = "unset", line = "unset", functions = "unset", parent = "unset", badProperty = "unset", wrongClass = "unset", badHandle = "unset");
initial begin
  $display("name=%s", name);
  $display("line=%s", line);
  $display("functions=%s", functions);
  $display("parent=%s", parent);
  $display("badProperty=%s", badProperty);
  $display("wrongClass=%s", wrongClass);
  $display("badHandle=%s", badHandle);
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
