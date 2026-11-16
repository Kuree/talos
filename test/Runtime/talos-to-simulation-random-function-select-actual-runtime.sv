// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 13.5.1/18.5.11: an input formal receives a copy of its
// actual, so selects in the function body index the formal's own range even
// when the actual is an equivalent packed select with another range.
// CHECK: select actual constant PASS
// CHECK-NEXT: select actual indexed PASS

function automatic bit low_clear(bit [1:0] w);
  return !w[0];
endfunction

class Constant;
  rand bit [7:0] v;
  rand bit a, b, c;
  constraint k {
    a == low_clear(v[5:4]);
    b == low_clear(v[3 -: 2]);
    c == low_clear(v[6 +: 2]);
  }
endclass

class Indexed;
  rand bit [7:0] v;
  rand bit a, b;
  int i = 5;
  constraint k {
    a == low_clear(v[i -: 2]);
    b == low_clear(v[i +: 2]);
  }
endclass

module top;
  initial begin
    static Constant c = new;
    static Indexed x = new;
    repeat (32) begin
      if (!c.randomize()) $fatal(1, "constant select randomize failed");
      if (c.a != !c.v[4] || c.b != !c.v[2] || c.c != !c.v[6])
        $fatal(1, "constant select relation violated: %b %b%b%b", c.v, c.a,
               c.b, c.c);
    end
    $display("select actual constant PASS");
    repeat (32) begin
      x.i = $urandom_range(1, 6);
      if (!x.randomize()) $fatal(1, "indexed select randomize failed");
      if (x.a != !x.v[x.i - 1] || x.b != !x.v[x.i])
        $fatal(1, "indexed select relation violated at %0d", x.i);
    end
    $display("select actual indexed PASS");
  end
endmodule
