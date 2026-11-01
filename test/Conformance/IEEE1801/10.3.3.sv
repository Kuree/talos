// CLAUSE: Class ID
// REQUIRES: upf
// XFAIL: *
// upf_query_object_type (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=upfPowerDomainT{{$}}
// CHECK: scope=upfHdlScopeT{{$}}
// CHECK: net=upfSupplyNetT{{$}}

// 1801-2018 10.3.3: a class ID is the class name in capitalized words with a upf prefix and T suffix.
module show #(parameter string domain = "unset", scope = "unset", net = "unset");
initial begin
  $display("domain=%s", domain);
  $display("scope=%s", scope);
  $display("net=%s", net);
end
endmodule
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
wire q;
leaf dut(q);
endmodule
