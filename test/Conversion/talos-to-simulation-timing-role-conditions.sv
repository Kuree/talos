// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 31.9.2: $setuphold and $recrem with nonnegative limits can see
// either event first, so one occurrence takes a timestamp under the timestamp
// condition and is checked under the timecheck condition.
module top;
  timeunit 1ns; timeprecision 1ns;
  logic c, d, s, t;
  reg n;
  specify
    $setuphold(posedge c, d, 3, 4, n, s, t);
    $recrem(posedge c, d, 3, 4, n, , t);
  endspecify
endmodule

// The primary slots carry the timecheck condition, then a shadow of each event
// carries the timestamp condition. Without one, its slots have no condition.
// CHECK: simulation.suspend.clock_set %[[C:[^,]*]], %[[D:[^,]*]], %[[C]], %[[D]], {{.*}} conditions 4 edges [1, 0, 1, 0] indices [0, 1, 2, 3]
// CHECK: simulation.suspend.clock_set %[[C2:[^,]*]], %[[D2:[^,]*]], %[[C2]], %[[D2]], {{.*}} conditions 2 edges [1, 0, 1, 0] indices [0, 1, -1, -1]
