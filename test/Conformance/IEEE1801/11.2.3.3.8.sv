// CLAUSE: set_power_state_by_handle
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: set=1{{$}}
// CHECK: on=FULL_ON q=1{{$}}
// CHECK: off=OFF q=x{{$}}
// CHECK: again=FULL_ON q=1{{$}}

// 1801-2018 11.2.3.3.8, 9.3.1: this is its example. ON and OFF are deferred on a supply set (4.7.4), so the
// state's simstate sets the functions: FULL_ON for ON and OFF for its CORRUPT, which the logic follows.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT ss, on, off;
upfSupplyTypeT power;
wire q;
leaf dut(q);
initial begin
  ss = upf_get_handle_by_name("/top/PD.primary");
  on = upf_get_handle_by_name("ON", ss);
  off = upf_get_handle_by_name("OFF", ss);
  $display("set=%0d", set_power_state_by_handle(ss, on));
  #10;
  power = get_supply_value("/top/PD.primary.power");
  $display("on=%s q=%b", power.state.name(), q);
  void'(set_power_state_by_handle(ss, off));
  #10;
  power = get_supply_value("/top/PD.primary.power");
  $display("off=%s q=%b", power.state.name(), q);
  void'(set_power_state_by_handle(ss, on));
  #10;
  power = get_supply_value("/top/PD.primary.power");
  $display("again=%s q=%b", power.state.name(), q);
  $finish;
end
endmodule
