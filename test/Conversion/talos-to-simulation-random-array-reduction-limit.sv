// RUN: %talos --std=1800-2023 -emit-talos %s | not talos-opt --lower-talos-to-sim=opt-level=0 -o /dev/null 2>&1 | FileCheck %s

// An array reduction constraint expands to one term per element (IEEE 1800-2023
// 18.5.7.2), under the same limit as a static foreach.
class C;
  rand bit [7:0] mem[257];
  // CHECK: [[@LINE+1]]:{{[0-9]+}}: error: array reduction constraint exceeds the static expansion limit of 256 elements
  constraint c { mem.sum() != 0; }
endclass

module top;
  C c = new;
  initial void'(c.randomize());
endmodule
