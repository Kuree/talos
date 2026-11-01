// CLAUSE: upf_object_in_class
// REQUIRES: upf
// XFAIL: *
// upf_object_in_class (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: member=1{{$}}
// CHECK: other=0{{$}}
// CHECK: root=1{{$}}
// CHECK: badClass=1{{$}}

// 1801-2018 11.1.2.3: 1 for a class in the object's membership, 0 for one outside it, and an error for a
// name that is no class. The first two are the clause's examples.
module show #(parameter string member = "unset", other = "unset", root = "unset", badClass = "unset");
initial begin
  $display("member=%s", member);
  $display("other=%s", other);
  $display("root=%s", root);
  $display("badClass=%s", badClass);
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
