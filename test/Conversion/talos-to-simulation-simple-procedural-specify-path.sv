// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DBAD -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=BAD

// IEEE 1800-2023 30.4.1 allows a variable as a module path destination. The
// always @* writer reads the path source (9.4.2.2), so each wake compares the
// source with its snapshot and delays the store by the path delay.
module cell_t(input wire a, input wire b, output reg q);
  timeunit 1ns; timeprecision 1ns;
  always @* q = a;
  specify
    (a => q) = 3;
`ifdef BAD
    // BAD: error: simple procedural specify path source is not observed by a direct event control or implicit sensitivity
    (b => q) = 3;
`endif
  endspecify
endmodule

// CHECK: procedural = <site = 0, wakeKind = 2, monitor = false>
// CHECK: simulation.logic.case_difference_mask
// CHECK: simulation.ref.store_inertial_path %{{.*}} to %{{.*}} write %{{.*}} active %{{.*}} masks[
