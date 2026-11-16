// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4.1: relations between two rand reals hold on the IEEE
// values, with both zeros equal. The sampler compares numeric coordinates
// directly; frozen operands keep their IEEE payloads, including NaN and Inf.
// CHECK: real relation random PASS
// CHECK-NEXT: real relation frozen PASS

class Less;
  rand shortreal a, b;
  constraint order { a < b; }
endclass

class Equal;
  rand shortreal a, b;
  constraint same { a == b; a < 0.0; }
endclass

module top;
  initial begin
    automatic Less less = new;
    automatic Equal equal = new;
    repeat (2) begin
      if (!less.randomize() || !(less.a < less.b))
        $fatal(1, "a < b violated: %g %g", less.a, less.b);
    end
    if (!equal.randomize() || equal.a != equal.b || !(equal.a < 0.0))
      $fatal(1, "a == b violated: %g %g", equal.a, equal.b);
    $display("real relation random PASS");

    less.a.rand_mode(0);
    less.a = -0.0;
    if (!less.randomize() || !(less.b > 0.0))
      $fatal(1, "b must exceed both zeros: %g", less.b);
    less.a = $bitstoshortreal(32'h7fc00000);
    if (less.randomize()) $fatal(1, "NaN < b solved");
    less.a = $bitstoshortreal(32'h7f800000);
    if (less.randomize()) $fatal(1, "+Inf < b solved");
    less.a.rand_mode(1);
    less.b.rand_mode(0);
    less.b = $bitstoshortreal(32'h7f800000);
    if (!less.randomize() || !(less.a < less.b)) $fatal(1, "a < +Inf failed");
    $display("real relation frozen PASS");
  end
endmodule
