// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/wide.sv | not talos-opt --talos-sim-prepare 2>&1 | FileCheck %s --check-prefix=WIDE
// RUN: %talos --std=1800-2023 -emit-talos %t/soft.sv | not talos-opt --talos-sim-prepare 2>&1 | FileCheck %s --check-prefix=SOFT
// RUN: %talos --std=1800-2023 -emit-talos %t/none.sv | not talos-opt --talos-sim-prepare 2>&1 | FileCheck %s --check-prefix=NONE
// RUN: %talos --std=1800-2023 -emit-talos %t/xz.sv | not talos-opt --talos-sim-prepare 2>&1 | FileCheck %s --check-prefix=XZ
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4, 7.5: constrained elements need a provable constant
// bound on size(). Unconstrained headers, soft bounds, absent bounds and
// X/Z-capable headers cast to a two-state value are diagnosed.
// WIDE: error: the size() bound 4294967295
// SOFT: error: the size() bound 4294967295
// NONE: error: constraints on the elements of a random dynamic array or queue require an always-active hard constraint
// XZ: error: the size() bound 2147483647

//--- wide.sv
class A;
  rand bit [31:0] len;
  rand bit [7:0] payload[];
  constraint c { payload.size() == len; foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

//--- soft.sv
class A;
  rand bit [31:0] len;
  rand bit [7:0] payload[];
  constraint c { soft len < 8'd10; payload.size() == len; foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

//--- none.sv
class A;
  rand bit [7:0] payload[];
  constraint c { foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

//--- xz.sv
class A;
  rand logic [7:0] len;
  rand bit [7:0] payload[];
  constraint c { len inside {[4:6]}; payload.size() == int'(len); foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

