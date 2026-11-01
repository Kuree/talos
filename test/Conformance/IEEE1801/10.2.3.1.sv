// CLAUSE: Property values and property identifiers
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.2.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=PAD{{$}}
// CHECK: line=1{{$}}
// CHECK: dir=UPF_DIR_IN{{$}}
// CHECK: parent=/top{{$}}

// 1801-2018 10.2.3.1: a query command returns a basic property as a string and a complex one as a UPF
// handle. Those strings are bound as checker parameters, the only channel phase 5 leaves (11.1.1).
module show #(parameter string name = "unset", line = "unset", dir = "unset", parent = "unset");
initial begin
  $display("name=%s", name);
  $display("line=%s", line);
  $display("dir=%s", dir);
  $display("parent=%s", parent);
end
endmodule
module top;
endmodule
