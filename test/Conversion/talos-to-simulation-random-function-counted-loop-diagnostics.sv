// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/wrap.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/body-write.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/dynamic.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/budget.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/unknown.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/real-conversion.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s

// Do not truncate loops that may wrap forever, whose counter changes in the
// body, whose bounds depend on random arguments, or which exceed the policy.
// Known counters and endpoints are required for this finite expansion path.
// Numeric real conversions cannot be treated as bit-vector extensions.
// CHECK: error: constraint function id must be a side-effect-free expression function or an admitted automatic statement body

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
