// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DAMBIGUOUS -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=AMBIGUOUS

// IEEE 1800-2023 31.4.4: the $width data event is the reference event's signal
// with the opposite edge, and 31.5 lets an edge descriptor set name the reference
// edge. A set that holds both a transition and its opposite has no opposite edge.
module top(input wire c, en);
  timeunit 1ns; timeprecision 1ns;
  reg n = 0;
  specify
`ifdef AMBIGUOUS
    // AMBIGUOUS: error: IEEE 1800-2017 Clause 31 system timing checks are retained in semantic IR but are not executable yet
    $width(edge [01, 10] c, 2, 0, n);
`else
    $width(edge [01] c &&& en, 2, 0, n);
    $width(edge [10, x0] c, 2, 0, n);
`endif
  endspecify
endmodule

// Descriptor classes are 01/0x/10/1x/x0/x1 in bits 0 to 5 over the 0x100 tag.
// The opposite of 01 is 10, and of 10 and x0 is 01 and x1. The condition applies
// to both events.
// CHECK: simulation.suspend.clock_set {{.*}} conditions 2 edges [257, 260]
// CHECK: simulation.suspend.clock_set {{.*}} conditions 0 edges [276, 289]
