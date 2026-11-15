// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/ok.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=OK
// RUN: %talos --std=1800-2023 -emit-talos %t/record.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=RECORD
// RUN: %talos --std=1800-2023 -emit-talos %t/array.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=ARRAY
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: numeric aggregate functions that only write their
// local/input copies run natively; writes to nonlocal struct members or array
// elements are side effects and are rejected.
// OK: simulation.random.function_stage
// RECORD: error: constraint function bad_record must be a side-effect-free expression function or an admitted automatic statement body
// ARRAY: error: constraint function bad_array must be a side-effect-free expression function or an admitted automatic statement body

//--- ok.sv
typedef bit [7:0] arr_t [3];
class C;
  rand bit [7:0] x, a, b;
  function automatic bit [7:0] good(arr_t p);
    arr_t q = p;
    q[2] = q[0] + q[1];
    return q[2];
  endfunction
  constraint c { x == good('{a, b, 8'd1}); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- record.sv
typedef struct { bit [7:0] lo; bit [7:0] hi; } pair_t;
class C;
  rand bit [7:0] x, y;
  pair_t state;
  bit [7:0] hist [4];
  function automatic bit [7:0] bad_record(bit [7:0] v);
    state.lo = v;
    return state.lo;
  endfunction
  constraint c { x == bad_record(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- array.sv
typedef struct { bit [7:0] lo; bit [7:0] hi; } pair_t;
class C;
  rand bit [7:0] x, y;
  pair_t state;
  bit [7:0] hist [4];
  function automatic bit [7:0] bad_array(bit [7:0] v);
    hist[1] = v;
    return hist[1];
  endfunction
  constraint c { x == bad_array(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
