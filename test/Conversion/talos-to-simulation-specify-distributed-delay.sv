// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DPARTIAL -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=PARTIAL

// IEEE 1800-2023 30.6: when a module contains both module path delays and
// distributed delays, the larger of the two is used for each path. The driver's
// delay is the distributed delay here, for each of the rise, fall and turn-off
// transitions.
module cell_t(input wire a, output wire y);
  timeunit 1ns; timeprecision 1ps;
`ifdef PARTIAL
  // PARTIAL: error: combining a state-dependent, edge-sensitive or partial specify path with an explicitly delayed driver is not executable yet
  buf #2 g(y, a);
  specify if (a) (a => y) = 4; endspecify
`else
  buf #(6, 2) g(y, a);
  specify (a => y) = (4, 4); endspecify
`endif
endmodule
module top;
  timeunit 1ns; timeprecision 1ps;
  logic a = 0;
  wire y;
  cell_t d(a, y);
endmodule

// Rise max(6, 4), fall max(2, 4), turn-off max(min(6, 2), min(4, 4)).
// CHECK: [[TURNOFF:%[0-9]+]] = simulation.time.constant 4000 {simulation.rematerialized}
// CHECK-NEXT: [[FALL:%[0-9]+]] = simulation.time.constant 4000 {simulation.rematerialized}
// CHECK-NEXT: [[RISE:%[0-9]+]] = simulation.time.constant 6000 {simulation.rematerialized}
// CHECK-NEXT: simulation.driver.drive_inertial {{.*}} after[[[RISE]], [[FALL]], [[TURNOFF]]]
