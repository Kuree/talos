// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 --execution-tier=native --top=solved %s -o native && ./native 2>&1 | FileCheck %s --check-prefix=SOLVED --implicit-check-not=ERROR
// RUN: cd %t && talos -O0 --execution-tier=bytecode --top=solved %s -o bytecode && ./bytecode 2>&1 | FileCheck %s --check-prefix=SOLVED --implicit-check-not=ERROR
// RUN: cd %t && talos -O0 --execution-tier=native --top=sets %s -o native && not ./native 2>&1 | FileCheck %s --check-prefix=SETS --implicit-check-not=F1.u3 --implicit-check-not=B1.u1 --implicit-check-not=B1.u2 --implicit-check-not=model.m1 --implicit-check-not=model.m2 --implicit-check-not='mask changed' --implicit-check-not=x=m=0 --implicit-check-not='y!=n=0'
// RUN: cd %t && talos -O0 --execution-tier=bytecode --top=sets %s -o bytecode && not ./bytecode 2>&1 | FileCheck %s --check-prefix=SETS --implicit-check-not=F1.u3 --implicit-check-not=B1.u1 --implicit-check-not=B1.u2 --implicit-check-not=model.m1 --implicit-check-not=model.m2 --implicit-check-not='mask changed' --implicit-check-not=x=m=0 --implicit-check-not='y!=n=0'
// RUN: cd %t && talos -O0 --execution-tier=native --top=clash %s -o native 2>&1 | FileCheck %s --check-prefix=CLASH-WARN
// RUN: cd %t && ./native | FileCheck %s --check-prefix=CLASH

// IEEE 1800-2023 17.7.2 on wide variables, which random draws would not hit. The
// clock and `want` change in one step, so the constraint uses the sampled `want`
// and the assertion the current `v`. `a |=> b` constrains the tick after `a`.
checker wide_checker(input bit clk, input bit [31:0] want);
  rand bit [31:0] v;
  rand bit [95:0] wide;
  rand bit a, b;
  rand struct packed { bit [3:0] hi, lo; } pair;
  m4: assume property (@(posedge clk) pair.hi == 4'h7);
  m0: assume property (@(posedge clk) v == want);
  m1: assume property (@(posedge clk) wide[95:64] == 32'hdeadbeef);
  m2: assume property (@(posedge clk) a |=> b);
  m3: assume property (@(posedge clk) !a |=> !b);
  always_ff @(posedge clk) $display("%0t want=%h v=%h wide=%h", $time, want, v, wide[95:64]);
endchecker
module solved;
  bit clk;
  bit [31:0] want = 32'h12345678;
  wide_checker check(clk, want);
  always #5 begin if (!clk) want = want + 1; clk = ~clk; end
  initial #21 $finish;
endmodule
// SOLVED: 5 want=12345678 v=12345678 wide=deadbeef
// SOLVED: 15 want=12345679 v=12345679 wide=deadbeef

// The assume sets of the example of 17.7.2. F1's holds u3 and F1.B1.u1, which reads
// q through the formal x, so q and m are solved together. u4 is excluded by its
// const cast actual and is only checked: r is 1 from the first tick on, while b is
// 0. r is inactive, as it is assigned. A checker's clocks can be a global clock.
checker c1(bit fclk, bit a, bit b);
  checker c2(bit bclk, bit x, bit y);
    rand bit m, n;
    u1: assume property (@(posedge bclk) x == m);
    u2: assume property (@(posedge bclk) y != n);
    always_ff @(posedge bclk) $display("x=m=%b y!=n=%b", x == m, y != n);
  endchecker
  rand bit q;
  bit r = 1;
  c2 B1(fclk, q + r, r);
  always_ff @(posedge fclk) r <= a || q;
  u3: assume property (@(posedge fclk) a != q);
  u4: assume property (@(posedge fclk) b == r);
  // A const free variable has a random value that never changes.
  rand const bit [31:0] mask;
  bit [31:0] first;
  bit seen;
  always_ff @(posedge fclk) begin
    if (seen && first != mask) $display("mask changed");
    first <= mask;
    seen <= 1;
  end
endchecker
checker observer(bit reset);
  default clocking @$global_clock; endclocking
  rand bit flag;
  m1: assume property (reset |=> !flag);
  m2: assume property (!reset && flag |=> flag);
endchecker
module sets;
  bit mclk, v1, v2, reset = 1;
  global clocking @(posedge mclk); endclocking
  c1 F1(mclk, v1, const'(v2));
  observer model(reset);
  always #5 mclk = ~mclk;
  initial begin #12 reset = 0; #18 $display("DONE"); $finish; end
endmodule
// SETS-DAG: F1.u4: simulation time 5
// SETS-DAG: DONE

// "When a solution attempt is unsuccessful, any resulting assumption failure(s) do
// not occur until an unsatisfied property is clocked and checked."
checker contradiction(input bit clk);
  rand bit v;
  m0: assume property (@(posedge clk) v) else $display("m0 v=%b", v);
  m1: assume property (@(posedge clk) !v) else $display("m1 v=%b", v);
endchecker
module clash;
  bit clk;
  contradiction check(clk);
  always #5 clk = ~clk;
  initial #6 $finish;
endmodule
// CLASH-WARN: warning: randomize hard constraints are statically unsatisfiable
// CLASH: {{m0 v=0|m1 v=1}}
