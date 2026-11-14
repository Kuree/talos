// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/proved.sv | talos-opt '--lower-talos-to-sim=opt-level=0' --canonicalize --cse | FileCheck %s --check-prefix=PROVED --implicit-check-not=simulation.random.function_stage
// RUN: %talos --std=1800-2023 -emit-talos %t/wrap.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// RUN: %talos --std=1800-2023 -emit-talos %t/dynamic.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// RUN: %talos --std=1800-2023 -emit-talos %t/zero-stride.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// REQUIRES: compiled-sampler

// IEEE 1800-2023 12.7.1 and 18.5.11: constant-stride for loops (++, --, +=K,
// -=K, i = i - K) and shift/counter while and do-while loops are
// proved finite and expanded into the solver relation with no staged native
// call (exact values: see the runtime test). Loops that never reach their
// bound, or whose bound is dynamic, use simulation.random.function_stage.

//--- proved.sv
class C;
  rand bit [7:0] x, y, z;
  function automatic int stride(int v);
    int s = v;
    for (int i = -3; i <= 3; i += 2) s += i + 1;   // 4
    for (int i = 6; i > 0; i = i - 2) s += i;      // 12
    return s;
  endfunction
  function automatic int whiles(int v);
    int s = v, n = 3;
    while (n > 0) begin s += n; n--; end           // 6
    do s += 100; while (n > 0);                    // 100, entered once
    for (bit [7:0] w = 8'd12; w != 0; w >>= 1) s++; // 4
    return s;
  endfunction
  function automatic bit [7:0] bump(bit [7:0] v);   // rand argument
    for (int i = 0; i < 4; i += 2) v++;
    return v;
  endfunction
  constraint r { x == stride(1) + whiles(0); y == bump(z); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
// PROVED: simulation.random.solve

//--- wrap.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (bit [1:0] i = 0; i != 3; i += 2) ;   // 0, 2, 0, ... never 3
    return value;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- dynamic.sv
class C;
  rand bit [7:0] x, y;
  function automatic bit [7:0] id(bit [7:0] value);
    for (int i = 0; i < value; i++) ;
    return value;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- zero-stride.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    for (bit [2:0] i = 0; i < 2; i += 8) ;    // 8 == 0 modulo 2**3
    return value;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
// STAGED: simulation.random.function_stage
