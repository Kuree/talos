// CLAUSE: Property ID
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: malformed={{$}}
// CHECK: hasName=1{{$}}
// CHECK: hasParent=1{{$}}
// CHECK: name=PD{{$}}
// CHECK: parent=/top{{$}}

// 1801-2018 10.3.4: property IDs are lowercase words joined by '_' with a upf prefix, such as upf_name.
// Every key of the all-properties query (11.1.2.1 Example 2) must have that form, and the two named work.
module show #(parameter string malformed = "unset", hasName = "unset", hasParent = "unset", name = "unset", parent = "unset");
initial begin
  $display("malformed=%s", malformed);
  $display("hasName=%s", hasName);
  $display("hasParent=%s", hasParent);
  $display("name=%s", name);
  $display("parent=%s", parent);
end
endmodule
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
wire q;
leaf dut(q);
endmodule
