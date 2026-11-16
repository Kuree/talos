// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/array.sv | talos-opt --talos-sim-prepare | FileCheck %s --check-prefix=ARRAY
// RUN: %talos --std=1800-2023 -emit-talos %t/queue.sv | talos-opt --talos-sim-prepare | FileCheck %s --check-prefix=QUEUE
// RUN: %talos --std=1800-2023 -emit-talos %t/wrap.sv | talos-opt --talos-sim-prepare | FileCheck %s --check-prefix=WRAP
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4, 7.5, 7.10: the solver shadow of a dynamic array or
// queue is sized from the bound of size(), inferred through header arithmetic.
// len in [4:68], len * 2 + 3 gives at most 139 elements. A result cast that
// wraps (8'(len * 2), len up to 200) must use the whole 8-bit domain: 255.
// ARRAY: simulation.unpacked_array<0 : 138 x
// QUEUE: simulation.unpacked_array<0 : 138 x
// WRAP: simulation.unpacked_array<0 : 254 x

//--- array.sv
class A;
  rand bit [7:0] len;
  rand bit [7:0] payload[];
  constraint c { len inside {[4:68]}; payload.size() == len * 2 + 3; foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

//--- queue.sv
class A;
  rand bit [7:0] len;
  rand bit [7:0] payload[$];
  constraint c { len inside {[4:68]}; payload.size() == len * 2 + 3; foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

//--- wrap.sv
class A;
  rand bit [7:0] len;
  rand bit [7:0] payload[];
  constraint c { len inside {[4:200]}; payload.size() == 8'(len * 2); foreach (payload[i]) payload[i] < 8'd9; }
endclass
module top; A o = new; initial void'(o.randomize()); endmodule

