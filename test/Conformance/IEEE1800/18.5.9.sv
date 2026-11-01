// CLAUSE: solve before invariant
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 18.5.9: solve-before changes the distribution (not the solution set): P(s=1)=1/2 with it, 1/5 without.
// CHECK: SOLVE_OK=1 PLAIN_OK=1

class Cs; rand bit s; rand bit [1:0] d; constraint k {solve s before d; s -> d == 0;} endclass
class Cn; rand bit s; rand bit [1:0] d; constraint k {s -> d == 0;} endclass
module top;
  Cs a = new;  Cn b = new;  int na, nb;
  initial begin
    repeat (500) begin
      if (!a.randomize() || (a.s && a.d != 0)) $fatal(1, "solve-before violated constraint");
      if (!b.randomize() || (b.s && b.d != 0)) $fatal(1, "plain violated constraint");
      na += a.s;  nb += b.s;
    end
    // solve s before d: s uniform (about 250 of 500). Without it all 5 solutions are equally likely: s=1 about 100.
    $display("SOLVE_OK=%b PLAIN_OK=%b", na > 200 && na < 300, nb > 60 && nb < 140);
  end
endmodule
