// CLAUSE: Basic UPF query commands
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties, upf_query_object_type, upf_object_in_class, upf_query_object_pathname (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: parent=/top/PD{{$}}
// CHECK: kind=upfPowerDomainT{{$}}
// CHECK: inStrategy=0{{$}}
// CHECK: absolute=/top/PD{{$}}

// 1801-2018 11.1.2: the four basic commands chain, because a handle returned by one is an argument of the next.
module show #(parameter string parent = "unset", kind = "unset", inStrategy = "unset", absolute = "unset");
initial begin
  $display("parent=%s", parent);
  $display("kind=%s", kind);
  $display("inStrategy=%s", inStrategy);
  $display("absolute=%s", absolute);
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
