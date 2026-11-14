// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/zero-shift.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/nonzero-exit.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/body-write.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/signed-widening.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/width-bound.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/repeat-bound.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/repeat-dynamic.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: unproved, dynamic, and large pure scalar
// bodies execute natively after their random arguments have been sampled.
// Conversion must preserve the complete loop, including local counter writes
// and numeric real casts. These compile-only probes include potentially
// nonterminating bodies and must never be executed or finitely truncated.
// CHECK: simulation.random.function_stage
// CHECK-SAME: SAMP

//--- zero-shift.sv
class C;
  rand bit [3:0] x;
  rand bit [9:0] y;
  function automatic int id(bit [9:0] value);
    for (id = 0; value != 0; value = value >> 0) begin
      id = 0;
    end
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- nonzero-exit.sv
class C;
  rand bit [3:0] x;
  rand bit [9:0] y;
  function automatic int id(bit [9:0] value);
    for (id = 0; value != 1; value = value >> 1) begin
      id = 0;
    end
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- body-write.sv
class C;
  rand bit [3:0] x;
  rand bit [9:0] y;
  function automatic int id(bit [9:0] value);
    for (id = 0; value != 0; value = value >> 1) begin
      id = 0;
      value = 1023;
    end
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- signed-widening.sv
class C;
  rand bit [3:0] x;
  rand bit signed [9:0] y;
  function automatic int id(bit signed [9:0] value);
    for (id = 0; value != 0; value = int'(value) >> 1) begin
      id = 0;
    end
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- width-bound.sv
class C;
  rand bit [3:0] x;
  rand bit [256:0] y;
  function automatic int id(bit [256:0] value);
    for (id = 0; value != 0; value = value >> 1) begin
      id = 0;
    end
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- repeat-bound.sv
class C;
  rand bit [3:0] x;
  rand bit [9:0] y;
  function automatic int id(bit [9:0] value);
    repeat (257) ;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- repeat-dynamic.sv
class C;
  rand bit [3:0] x;
  rand bit [9:0] y;
  function automatic int id(bit [9:0] value);
    repeat (value) ;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule
