// CLAUSE: Native HDL representation
// REQUIRES: upf
// XFAIL: *
// upf_create_object_mirror (11.2.3.4.2) and the native HDL types of Table 37 are not in the UPF package.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: handles=/top/VDD /top/CORE.ON /top/PD{{$}}
// CHECK: off=OFF 0 CORRUPT{{$}}
// CHECK: on=FULL_ON 900000 1 NORMAL{{$}}
// CHECK: bits=96 33 33{{$}}

// 1801-2018 11.2.2.3 Tables 37 and 38: objects with dynamic properties have a native struct with a handle
// and the dynamic value. Mirrors of a net, a state and a domain must track the supply while their handles
// stay valid for other queries.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfSupplyNetT net;
upfPowerStateT on_state;
upfPowerDomainT domain;
wire q;
leaf dut(q);
initial begin
  void'(upf_create_object_mirror("/top/VDD", "net"));
  void'(upf_create_object_mirror("/top/CORE.ON", "on_state"));
  void'(upf_create_object_mirror("/top/PD", "domain"));
  #1;
  $display("handles=%s %s %s", upf_query_object_pathname(net.handle), upf_query_object_pathname(on_state.handle),
           upf_query_object_pathname(domain.handle));
  $display("off=%s %0d %s", net.current_value.state.name(), on_state.is_active, domain.current_simstate.name());
  void'(supply_on("/top/VDD", 0.9));
  void'(supply_on("/top/VSS", 0.0));
  #1;
  $display("on=%s %0d %0d %s", net.current_value.state.name(), net.current_value.voltage, on_state.is_active, domain.current_simstate.name());
  $display("bits=%0d %0d %0d", $bits(upfSupplyObjT), $bits(upfPowerStateObjT), $bits(upfBooleanObjT));
  $finish;
end
endmodule
