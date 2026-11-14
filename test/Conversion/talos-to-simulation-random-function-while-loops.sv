// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/proved.sv | talos-opt '--lower-talos-to-sim=opt-level=0' --canonicalize --cse | FileCheck %s --check-prefix=PROVED --implicit-check-not=simulation.random.function_stage
// RUN: %talos --std=1800-2023 -emit-talos %t/no-progress.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// RUN: %talos --std=1800-2023 -emit-talos %t/conditional-update.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// RUN: %talos --std=1800-2023 -emit-talos %t/dynamic.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=STAGED
// REQUIRES: compiled-sampler

// IEEE 1800-2023 12.7.4, 12.7.5 and 18.5.11: while and do...while loops with
// an unconditional modular counter or right-shift update, break/continue and
// a post-test entry are proved and expanded (no staged call; values: runtime test).
// Loops without provable progress, or with a random-argument bound, execute
// natively with simulation.random.function_stage after sampling.

//--- proved.sv
class C;
  rand bit [7:0] x, y, z;
  function automatic int f(int v);
    int s = v, n = 8;
    while (n > 0) begin
      n -= 3;                      // n: 8 -> 5, 5 -> 2 (skip), 2 -> -1
      if (n == 2) continue;
      s += n;                      // 32 + 5 - 1
    end
    do s += 10; while (0 > 1);     // post-test: entered once
    for (int k = 0; k < 100; k++) begin
      s++;
      if (k == 4) break;           // 5 more
    end
    return s;
  endfunction
  function automatic bit [7:0] bump(bit [7:0] v);   // rand argument
    int n = 0;
    do begin n++; v >>= 1; end while (v != 0);   // shift progress
    v = n;
    return v;
  endfunction
  constraint r { x == f(32); y == bump(z); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
// PROVED: simulation.random.solve

//--- no-progress.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    int n = 3;
    while (n > 0) begin end       // never terminates: must not be unrolled
    return value;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- conditional-update.sv
class C;
  rand bit x, y;
  function automatic bit id(bit value);
    int n = 3;
    while (n > 0) begin if (value) n--; end   // update is conditional
    return value;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- dynamic.sv
class C;
  rand bit [7:0] x, y;
  function automatic bit [7:0] id(bit [7:0] value);
    bit [7:0] n = 0;
    while (n < value) n++;         // bound depends on a sampled argument
    return n;
  endfunction
  constraint r { x == id(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
// STAGED: simulation.random.function_stage
