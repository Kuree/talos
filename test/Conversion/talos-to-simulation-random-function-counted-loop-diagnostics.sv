// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/wrap.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/body-write.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/dynamic.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/budget.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/unknown.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/real-conversion.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: unproved, dynamic, and large pure scalar
// bodies execute natively after their random arguments have been sampled.
// Conversion must preserve the complete loop, including local counter writes
// and numeric real casts. These compile-only probes include potentially
// nonterminating bodies and must never be executed or finitely truncated.
// CHECK: simulation.random.function_stage
// CHECK-SAME: SAMP

//--- wrap.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (bit [1:0] i = 0; i <= 3; i++) ;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- body-write.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (int i = 0; i < 3; i++) i = 0;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- dynamic.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (int i = 0; i < value; i++) ;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- budget.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (int i = 0; i < 257; i++) ;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- unknown.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (logic [1:0] i = 'x; i < 3; i++) ;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule

//--- real-conversion.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (int i = -1; real'(i) < real'(2); ++i) ;
    return value;
  endfunction
  constraint relation { x == id(y); }
endclass
module top;
  C object = new;
  initial void'(object.randomize());
endmodule
