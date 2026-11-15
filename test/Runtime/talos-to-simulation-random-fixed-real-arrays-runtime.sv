// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4/18.8: every fixed unpacked real/shortreal array element
// is a random variable with its own rand_mode bit. Constant-index constraints
// hold, frozen elements keep their exact IEEE payload (NaN, Inf, -0.0), failed
// requests leave all fields unchanged, and scope randomization covers arrays.
// CHECK: constants PASS
// CHECK-NEXT: modes PASS
// CHECK-NEXT: frozen payloads PASS
// CHECK-NEXT: rollback PASS
// CHECK-NEXT: scope PASS

class Packet;
  rand real d[4];
  rand shortreal s[2][2];
  constraint c {
    d[1] > 1.0; d[1] < 2.0;
    d[3] == 2.5;
    s[1][0] == 0.5;
    s[0][1] < 0.25;
  }
endclass

module top;
  Packet p = new;
  real a[3];
  shortreal sa[2];
  initial begin
    int ok;
    real keep[4];
    shortreal skeep[2][2];
    real nan, inf, nz;
    nan = $bitstoreal(64'h7ff8000000000001);
    inf = $bitstoreal(64'h7ff0000000000000);
    nz  = $bitstoreal(64'h8000000000000000);

    repeat (8) begin
      ok = p.randomize();
      if (!ok) $fatal(1, "randomize failed");
      if (!(p.d[1] > 1.0 && p.d[1] < 2.0)) $fatal(1, "d[1] range");
      if (p.d[3] != 2.5) $fatal(1, "d[3]");
      if (p.s[1][0] != 0.5) $fatal(1, "s[1][0]");
      if (!(p.s[0][1] < 0.25)) $fatal(1, "s order");
      // Unconstrained elements stay finite (18.4.1).
      if ($realtobits(p.d[0])[62:52] == 11'h7ff)
        $fatal(1, "d[0] not finite");
    end
    $display("constants PASS");

    // Per-element rand_mode (18.8): only d[0] is frozen.
    p.d[0] = 3.25;
    p.d[0].rand_mode(0);
    repeat (4) begin
      ok = p.randomize();
      if (!ok || p.d[0] != 3.25) $fatal(1, "frozen d[0] changed");
    end
    if (p.d[2].rand_mode() != 1 || p.d[0].rand_mode() != 0)
      $fatal(1, "mode query");
    p.d[0].rand_mode(1);
    $display("modes PASS");

    // Frozen NaN / Inf / -0.0 payloads survive (18.8) when nothing
    // constrains them.
    p.d[0] = nan; p.d[2] = nz; p.s[0][0] = $bitstoreal(64'h0);
    p.d[0].rand_mode(0); p.d[2].rand_mode(0);
    ok = p.randomize();
    if (!ok) $fatal(1, "nonfinite frozen failed");
    if ($realtobits(p.d[0]) != 64'h7ff8000000000001) $fatal(1, "NaN payload");
    if ($realtobits(p.d[2]) != 64'h8000000000000000) $fatal(1, "-0.0 payload");
    p.d[2] = inf;
    ok = p.randomize();
    if (!ok || $realtobits(p.d[2]) != 64'h7ff0000000000000)
      $fatal(1, "Inf payload");
    $display("frozen payloads PASS");

    // A frozen value that contradicts a constraint fails and rolls back.
    p.d[1].rand_mode(0);
    p.d[1] = 5.0;
    foreach (keep[i]) keep[i] = p.d[i];
    foreach (skeep[i, j]) skeep[i][j] = p.s[i][j];
    ok = p.randomize();
    if (ok) $fatal(1, "contradiction accepted");
    foreach (keep[i])
      if ($realtobits(keep[i]) != $realtobits(p.d[i])) $fatal(1, "d rolled");
    foreach (skeep[i, j])
      if (skeep[i][j] != p.s[i][j]) $fatal(1, "s rolled");
    p.d[1].rand_mode(1);
    ok = p.randomize();
    if (!ok) $fatal(1, "recovery failed");
    $display("rollback PASS");

    // Scope randomization with arrays of both precisions.
    repeat (4) begin
      ok = std::randomize(a, sa) with {
        a[0] == 1.5; a[1] > 2.0; a[2] == -4.0; sa[0] < 0.25; sa[1] == 8.0;
      };
      if (!ok) $fatal(1, "scope failed");
      if (a[0] != 1.5 || !(a[1] > 2.0) || a[2] != -4.0 ||
          !(sa[0] < 0.25) || sa[1] != 8.0) $fatal(1, "scope values");
    end
    $display("scope PASS");
  end
endmodule
