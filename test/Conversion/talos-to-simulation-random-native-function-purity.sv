// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/native.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=NATIVE
// RUN: %talos --std=1800-2023 -emit-talos %t/staged.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// RUN: %talos --std=1800-2023 -emit-talos %t/static.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=STATIC
// RUN: %talos --std=1800-2023 -emit-talos %t/nonlocal.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=NONLOCAL
// RUN: %talos --std=1800-2023 -emit-talos %t/rng.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=RNG
// RUN: %talos --std=1800-2023 -emit-talos %t/alloc.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=ALLOC
// RUN: %talos --std=1800-2023 -emit-talos %t/real.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=REAL
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: a pure function too long to expand is retained as an
// ordinary call. State-only actuals call it before the solve; random
// actuals (integral or real) go through simulation.random.function_stage.
// Impure bodies (static local, nonlocal write, nested RNG call, allocation,
// nonlocal real write) are rejected, transitively through callees.

// NATIVE: simulation.class.direct_call @unit_
// NATIVE-NOT: simulation.random.function_stage
// NATIVE: simulation.random.solve

// STAGED: simulation.random.function_stage
// STAGED: simulation.random.function_stage
// STATIC: error: constraint function f_static must be a side-effect-free expression function or an admitted automatic statement body
// NONLOCAL: error: constraint function f_nonlocal must be a side-effect-free expression function or an admitted automatic statement body
// RNG: error: constraint function f_rng must be a side-effect-free expression function or an admitted automatic statement body
// ALLOC: error: constraint function f_alloc must be a side-effect-free expression function or an admitted automatic statement body
// REAL: error: constraint function f_real must be a side-effect-free expression function or an admitted automatic statement body

//--- native.sv
class C;
  rand bit [7:0] y;
  bit [7:0] n = 3;
  function automatic bit [7:0] f(bit [7:0] v);
    bit [7:0] a = 0;
    for (int i = 0; i < 513; i++) a = a + v;
    return a;
  endfunction
  constraint c { y == f(n); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule

//--- staged.sv
class C;
  rand bit [7:0] x, y;
  function automatic bit [7:0] f(bit [7:0] v);
    bit [7:0] a = 0;
    for (int i = 0; i < 513; i++) a = a + v;
    return a;
  endfunction
  constraint c { y == f(x); }
endclass
class D;
  rand real r, q;
  function automatic real h(real v);
    real a = 0.0;
    for (int i = 0; i < 513; i++) a = v + v;
    return a;
  endfunction
  constraint c { q == h(r); }
endclass
module top;
  C o = new;
  D d = new;
  initial begin
    void'(o.randomize());
    void'(d.randomize());
  end
endmodule

//--- static.sv
class Leaf;
  bit q;
endclass
class C;
  rand bit [7:0] y;
  rand real ry;
  bit [7:0] cnt;
  real rc;
  function automatic bit [7:0] g(bit [7:0] v);
    return v + 8'($urandom);
  endfunction
  function automatic bit [7:0] f_static(bit [7:0] v);
    static bit [7:0] a = 0;
    for (int i = 0; i < 513; i++) a = a + v;
    return a;
  endfunction
  constraint c { y == f_static(8'd3); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule

//--- nonlocal.sv
class Leaf;
  bit q;
endclass
class C;
  rand bit [7:0] y;
  rand real ry;
  bit [7:0] cnt;
  real rc;
  function automatic bit [7:0] g(bit [7:0] v);
    return v + 8'($urandom);
  endfunction
  function automatic bit [7:0] f_nonlocal(bit [7:0] v);
    for (int i = 0; i < 513; i++) cnt = cnt + v;
    return cnt;
  endfunction
  constraint c { y == f_nonlocal(8'd3); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule

//--- rng.sv
class Leaf;
  bit q;
endclass
class C;
  rand bit [7:0] y;
  rand real ry;
  bit [7:0] cnt;
  real rc;
  function automatic bit [7:0] g(bit [7:0] v);
    return v + 8'($urandom);
  endfunction
  function automatic bit [7:0] f_rng(bit [7:0] v);
    bit [7:0] a = 0;
    for (int i = 0; i < 513; i++) a = a + g(v);
    return a;
  endfunction
  constraint c { y == f_rng(8'd3); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule

//--- alloc.sv
class Leaf;
  bit q;
endclass
class C;
  rand bit [7:0] y;
  rand real ry;
  bit [7:0] cnt;
  real rc;
  function automatic bit [7:0] g(bit [7:0] v);
    return v + 8'($urandom);
  endfunction
  function automatic bit [7:0] f_alloc(bit [7:0] v);
    Leaf l = new;
    for (int i = 0; i < 513; i++) l.q = ~l.q;
    return v + 8'(l.q);
  endfunction
  constraint c { y == f_alloc(8'd3); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule

//--- real.sv
class Leaf;
  bit q;
endclass
class C;
  rand bit [7:0] y;
  rand real ry;
  bit [7:0] cnt;
  real rc;
  function automatic bit [7:0] g(bit [7:0] v);
    return v + 8'($urandom);
  endfunction
  function automatic real f_real(real v);
    for (int i = 0; i < 513; i++) rc = rc + v;
    return rc;
  endfunction
  constraint c { ry == f_real(1.0); }
endclass
module top;
  C o = new;
  initial void'(o.randomize());
endmodule
