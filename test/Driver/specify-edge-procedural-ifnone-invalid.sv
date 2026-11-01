// RUN: not talos -emit-sim %s -o /dev/null 2>&1 | FileCheck %s
module procedural_ifnone(input wire clock, data, output logic q);
  always @(posedge clock)
    q = data;
  specify
    ifnone (clock => q) = 2;
  endspecify
endmodule
// Clause 30.4.4.4 makes ifnone a simple-path declaration, which fires on any
// change of its source (30.4.1). The writer wakes only on posedge, so it
// cannot observe every transition of the source.
// CHECK: error: simple procedural specify path source is not observed by a direct event control or implicit sensitivity
