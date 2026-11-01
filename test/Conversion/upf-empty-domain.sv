// RUN: %split-file %s %t
// RUN: talos --upf %t/power.upf -emit-sim %t/design.sv -o - | FileCheck %s

// A domain's elements (IEEE 1801-2018 6.20) may hold nothing a power state can
// corrupt, such as an empty leaf. Such a domain lowers to nothing.

//--- power.upf
create_power_domain P -elements dut
create_supply_net V -domain P

//--- design.sv
module child;
endmodule
module top;
  child dut();
  logic q = 1;
endmodule

// CHECK: simulation.design
// CHECK-NOT: upf.
// CHECK: simulation.storage.decl {{[0-9]+}} in {{[0-9]+}} : !simulation.logic<1> design hierarchy "top.q"
// CHECK-NOT: upf.
