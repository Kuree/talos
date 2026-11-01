// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 E.2: `default_decay_time applies to trireg nets without a
// declared decay time in the modules after it, until the next directive or
// `resetall; the operand is in the module's time units.
`default_decay_time 2
module decayed;
  timeunit 1ns; timeprecision 100ps;
  trireg declared_decay_nets_keep_theirs;
  trireg #(0, 0, 5) explicit_decay;
  trireg #(3, 4) two_delays;
endmodule
`default_decay_time 1.5
module real_decay;
  timeunit 1ns; timeprecision 100ps;
  trireg q;
endmodule
`default_decay_time infinite
module infinite_decay;
  timeunit 1ns; timeprecision 100ps;
  trireg q;
endmodule
`default_decay_time 7
`resetall
module reset;
  timeunit 1ns; timeprecision 100ps;
  trireg q;
endmodule

`default_decay_time 2
module zz_assigned;
  timeunit 1ns; timeprecision 100ps;
  trireg assigned = 1'bz;
  trireg #(1, 1, 5) assigned_with_decay = 1'bz;
endmodule

// 100 ps ticks: 2 ns is 20 ticks and 1.5 ns is 15; an explicit decay wins.
// CHECK: hierarchy "decayed.declared_decay_nets_keep_theirs"
// CHECK-SAME: propagation_delays = array<i64: 0, 0, 20>
// CHECK: hierarchy "decayed.explicit_decay"
// CHECK-SAME: propagation_delays = array<i64: 0, 0, 50>
// CHECK: hierarchy "decayed.two_delays"
// CHECK-SAME: propagation_delays = array<i64: 30, 40, 20>
// `infinite and `resetall leave the net without any decay delay.
// CHECK: hierarchy "infinite_decay.q"
// CHECK-NOT: propagation_delays
// CHECK: hierarchy "real_decay.q"
// CHECK-SAME: propagation_delays = array<i64: 0, 0, 15>
// CHECK: hierarchy "reset.q"
// CHECK-NOT: propagation_delays
// A declaration assignment takes the other delays, but the decay stays the net's.
// CHECK: hierarchy "zz_assigned.assigned"
// CHECK-SAME: propagation_delays = array<i64: 0, 0, 20>
// CHECK: hierarchy "zz_assigned.assigned_with_decay"
// CHECK-SAME: propagation_delays = array<i64: 0, 0, 50>
