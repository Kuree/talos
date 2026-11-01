// CLAUSE: Base classes
// REQUIRES: upf
// XFAIL: *
// upf_object_in_class (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: strategy=1{{$}}
// CHECK: boundary=1{{$}}
// CHECK: domainStrategy=0{{$}}
// CHECK: domainExtent=1{{$}}
// CHECK: netExtent=0{{$}}

// 1801-2018 10.4.5 Table 16: abstract base classes group objects that share properties, and their class
// IDs work in upf_object_in_class. A domain has extents but is no strategy; a net has neither.
module show #(parameter string strategy = "unset", boundary = "unset", domainStrategy = "unset", domainExtent = "unset", netExtent = "unset");
initial begin
  $display("strategy=%s", strategy);
  $display("boundary=%s", boundary);
  $display("domainStrategy=%s", domainStrategy);
  $display("domainExtent=%s", domainExtent);
  $display("netExtent=%s", netExtent);
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
