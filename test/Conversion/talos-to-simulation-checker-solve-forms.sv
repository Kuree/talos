// RUN: talos -emit-slang -DDISABLE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=DISABLE
// RUN: talos -emit-slang -DINITIAL %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=INITIAL
// RUN: talos -emit-slang -DCLOCKING %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=CLOCKING
// RUN: talos -emit-slang -DPROGRAM %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=PROGRAM
// RUN: talos -emit-slang -DCHECKED %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=CHECKED
// RUN: talos -emit-slang -DUNSOLVABLE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=UNSOLVABLE
// RUN: talos -emit-slang -DCLOSURE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=CLOSURE
// RUN: talos -emit-slang -DAUTOMATIC %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=AUTOMATIC

// IEEE 1800-2023 17.7.2: the forms an assume set takes for its solve.
`ifdef DISABLE
// 16.12: an assumption does not hold anything while it is disabled.
checker c(input bit clk, input bit reset);
  rand bit v, w;
  m0: assume property (@(posedge clk) disable iff (reset) v);
  m1: assume property (@(posedge clk) disable iff (reset) v |=> w);
endchecker
module top;
  bit clk, reset;
  c inst(clk, reset);
endmodule
`elsif INITIAL
// 17.7: the first time step holds the value of the initialization, and only that
// variable. A set of initialized variables alone has nothing to solve there.
checker c(input bit clk);
  rand bit [7:0] v = 8'h5a, w;
  m0: assume property (@(posedge clk) w == v + 1);
endchecker
checker d(input bit clk);
  rand bit [7:0] only = 8'h11;
  m0: assume property (@(posedge clk) only != 8'h11);
endchecker
module top;
  bit clk;
  c first(clk);
  d second(clk);
endmodule
`elsif CLOCKING
// 14.13: the event of a clocking block fires in the Observed region, too late for
// the solve, which so waits on the block's event expression, `iff` included.
checker c(input bit [7:0] s);
  rand bit [7:0] v;
  m0: assume property (@(top.cb) v == s);
endchecker
module top;
  bit clk, enable;
  bit [7:0] s;
  clocking cb @(posedge clk iff enable); endclocking
  c inst(s);
endmodule
`elsif PROGRAM
// The solve precedes the Observed region for an instance in a program too.
checker c(input bit clk, input bit [7:0] s);
  rand bit [7:0] v;
  m0: assume property (@(posedge clk) v == s);
endchecker
module top;
  bit clk;
  bit [7:0] s;
endmodule
program p;
  c inst(top.clk, top.s);
endprogram
`elsif CHECKED
// A variable only an unreadable assumption constrains is kept, which holds that
// assumption more often than a random draw would.
checker c(input bit clk, input bit [7:0] s);
  rand bit [7:0] kept, solved;
  m0: assume property (@(posedge clk) solved == s);
  m1: assume property (@(posedge clk) $stable(kept));
endchecker
module top;
  bit clk;
  bit [7:0] s;
  c inst(clk, s);
endmodule
`elsif UNSOLVABLE
// The runtime solver has no X or Z constants, so these are only checked. A
// comparison with a variable holding them is left to the solver.
checker c(input bit clk);
  rand bit [7:0] v, w;
  logic [7:0] pattern;
  m0: assume property (@(posedge clk) v ==? 8'b1xxx_xxxx);
  m1: assume property (@(posedge clk) w === pattern);
endchecker
module top;
  bit clk;
  c inst(clk);
endmodule
`elsif CLOSURE
// F1 solves m with x == m, so u2 on the same variable has to be in its set too.
checker c1(bit clk);
  checker c2(bit bclk, bit x);
    rand bit m;
    u1: assume property (@(posedge bclk) x == m);
    u2: assume property (@(posedge bclk) m == 1);
  endchecker
  rand bit q;
  c2 B1(clk, q);
endchecker
module top;
  bit clk;
  c1 F1(clk);
endmodule
`elsif AUTOMATIC
// A solve has no process with the value of an automatic actual, so the assumption
// reading it is only checked, and nothing else constrains v.
checker c(event e, logic [7:0] a);
  rand bit [7:0] v;
  m0: assume property (@e v == a);
endchecker
module top;
  bit clk;
  always @(posedge clk) begin
    automatic logic [7:0] x = 3;
    c inst(posedge clk, x);
  end
endmodule
`endif

// The condition is read as it is, and an attempt of `|=>` only starts while not
// disabled.
// DISABLE: simulation.storage.decl 1 in {{.*}}"top.reset"
// DISABLE: repeating_always_wait
// DISABLE-NEXT: ^bb2(
// DISABLE-NEXT: simulation.random.state
// DISABLE-NEXT: %[[RESET:[0-9]+]] = simulation.ref.load %arg2
// DISABLE-NEXT: arith.constant
// DISABLE-NEXT: arith.xori %[[RESET]]
// DISABLE: simulation.random.solve
// DISABLE: simulation.ref.store %{{[0-9]+}} to %arg3
// DISABLE: simulation.ref.store %{{[0-9]+}} to %arg4
// DISABLE: %[[AGAIN:[0-9]+]] = simulation.ref.load %arg2
// DISABLE: %[[ENABLED:[0-9]+]] = arith.xori %[[AGAIN]]
// DISABLE: arith.andi %[[ENABLED]]

// INITIAL: simulation.storage.decl 1 in {{.*}}"top.first.v"
// INITIAL: simulation.storage.decl 2 in {{.*}}"top.first.w"
// INITIAL: repeating_always_wait
// INITIAL-NEXT: ^bb2:
// INITIAL-NEXT: %[[NOW:[0-9]+]] = simulation.time.now %arg0
// INITIAL: %[[LATER:[0-9]+]] = arith.cmpi ne, %[[NOW]]
// INITIAL-NEXT: cf.cond_br %[[LATER]], ^bb3, ^bb4
// INITIAL: simulation.ref.store %{{[0-9]+}} to %arg2
// INITIAL-NEXT: simulation.ref.store %{{[0-9]+}} to %arg3
// INITIAL-NEXT: cf.br ^bb1
// INITIAL-NOT: to %arg2
// INITIAL: simulation.ref.store %{{[0-9]+}} to %arg3
// INITIAL-NEXT: cf.br ^bb1
// INITIAL: repeating_always_wait
// INITIAL-NEXT: ^bb2:
// INITIAL-NEXT: %[[NOW:[0-9]+]] = simulation.time.now %arg0
// INITIAL: %[[LATER:[0-9]+]] = arith.cmpi ne, %[[NOW]]
// INITIAL-NEXT: cf.cond_br %[[LATER]], ^bb3, ^bb1

// CLOCKING: simulation.storage.decl 0 in {{.*}}"top.clk"
// CLOCKING: simulation.storage.decl 1 in {{.*}}"top.enable"
// CLOCKING: simulation.suspend.edge_iff posedge %arg1 iff %arg2 {{.*}}repeating_always_wait

// PROGRAM: simulation.func private @[[SOLVE:unit_[0-9]+]]({{.*}}domain = 0 : i32{{.*}}home_region = 2 : i32
// PROGRAM-NOT: simulation.func private
// PROGRAM: repeating_always_wait

// CHECKED: repeating_always_wait
// CHECKED-NOT: simulation.ref.store
// CHECKED: simulation.ref.store %{{[0-9]+}} to %arg3
// CHECKED-NEXT: cf.br ^bb1

// UNSOLVABLE: simulation.storage.decl {{[0-9]+}} in {{.*}}"top.inst.v"
// UNSOLVABLE: simulation.storage.decl [[W:[0-9]+]] in {{.*}}"top.inst.w"
// UNSOLVABLE: repeating_always_wait
// UNSOLVABLE: simulation.random.solve
// UNSOLVABLE: simulation.ref.store %{{[0-9]+}} to %arg2
// UNSOLVABLE-NEXT: cf.br ^bb1

// F1 pins m to 1 and takes q from it, with nothing left random.
// CLOSURE: simulation.storage.decl 1 in {{.*}}"top.F1.q"
// CLOSURE: simulation.storage.decl 2 in {{.*}}"top.F1.B1.m"
// CLOSURE: repeating_always_wait
// CLOSURE: repeating_always_wait
// CLOSURE: arith.constant {{.*}}-2 : i64
// CLOSURE-NEXT: %[[CLEARED:[0-9]+]] = arith.andi
// CLOSURE-NEXT: arith.constant {{.*}} 1 : i64
// CLOSURE-NEXT: arith.ori %[[CLEARED]]
// CLOSURE: simulation.ref.store %{{[0-9]+}} to %arg2
// CLOSURE-NEXT: simulation.ref.store %{{[0-9]+}} to %arg3

// Nothing is solved, and the only process waiting on the clock is the module's.
// AUTOMATIC-NOT: simulation.random.solve
