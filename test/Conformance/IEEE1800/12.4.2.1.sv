// CLAUSE: unique if overlap first
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 12.4.2.1: the overlapping unique-if is reported once; the glitch in always_comb a1 is flushed and not reported.
// CHECK: unique if violation
// CHECK: out=1
// CHECK: z=1
// CHECK-NOT: violation

module top;
  int value = 2, out;  bit a, b, c, not_a, z;
  always_comb not_a = !a;
  always_comb begin : a1
    u1: unique if (a) z = a | b; else if (not_a) z = a | c;
  end
  initial begin
    unique if (value > 0) out = 1; else if (value < 9) out = 2;   // real overlap: reported
    #1; $display("out=%0d", out);
    a = 1; #1; $display("z=%b", z);   // zero-delay glitch (LRM example): must not be reported
  end
endmodule
