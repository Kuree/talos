// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4.1/18.5: binary64 equality to a constant leaves 2^2044
// coordinate assignments per component. The exact model counter must propagate
// the constant through the arithmetic circuit instead of expanding it (this
// took ~50 s). Also checks rollback on a frozen contradiction (18.8).
// CHECK: real equality PASS
// CHECK-NEXT: real equality rollback PASS

class P;
  rand real a0, a1, a2, a3;
  rand real b2;
  constraint c {
    a2 == b2;
    a0 == 0.5; a1 == 0.5; a2 == 0.5; a3 == 0.5;
  }
endclass

module top;
  P p = new;
  initial begin
    int ok;
    ok = p.randomize();
    if (!ok) $fatal(1, "randomize failed");
    if (p.a0 != 0.5 || p.a1 != 0.5 || p.a2 != 0.5 || p.a3 != 0.5)
      $fatal(1, "a");
    if (p.b2 != 0.5) $fatal(1, "b2");
    $display("real equality PASS");
    p.a1.rand_mode(0);
    p.a1 = 0.25;
    ok = p.randomize();
    if (ok) $fatal(1, "frozen contradiction accepted");
    if (p.a1 != 0.25 || p.a0 != 0.5 || p.b2 != 0.5) $fatal(1, "rollback");
    $display("real equality rollback PASS");
  end
endmodule
