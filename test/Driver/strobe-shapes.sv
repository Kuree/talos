// RUN: talos -O3 %s -o %t
// RUN: %t > %t.out
// RUN: FileCheck %s < %t.out

// IEEE 1800-2023 21.2.2: $strobe and $fstrobe display their arguments at the
// end of the time step, from the Postponed region (4.4.2.9): after the NBAs
// (n, a, w) and after a blocking write that follows the strobe (m), from a
// clocked owner, a repeat loop, a task and an initial procedure. A generated
// owner takes a checkpoint in the activation that strobes. The text is what
// every other tier prints.
module top;
  logic clk = 0;
  logic [7:0] n = 0, a = 0, m = 0, w = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) n <= n + 1;
  always_ff @(posedge clk) begin
    a <= n * 3;
    if (n[1:0] == 2'd1) $strobe("A t=%0t n=%0d a=%0d", $time, n, a);
    if (n[1:0] == 2'd1) $strobe("B t=%0t n=%0d", $time, n);
    if (n[2:0] == 3'd2) $fstrobe(32'h1, "F t=%0t a=%0d", $time, a);
  end
  always @(posedge clk) if (n == 8'd9) repeat (2) $strobe("R n=%0d w=%0d", n, w);
  task t; $strobe("T n=%0d m=%0d", n, m); endtask
  always @(posedge clk) if (n == 8'd6) begin t(); m = 7; end
  always @(posedge clk) w <= n + 50;
  initial begin #33 $strobe("I t=%0t m=%0d", $time, m); m = 100; end
  initial #160 $finish;
endmodule

// CHECK: A t=15 n=2 a=3
// CHECK-NEXT: B t=15 n=2
// CHECK-NEXT: F t=25 a=6
// CHECK-NEXT: I t=33 m=100
// CHECK-NEXT: A t=55 n=6 a=15
// CHECK-NEXT: B t=55 n=6
// CHECK-NEXT: T n=7 m=7
// CHECK-NEXT: A t=95 n=10 a=27
// CHECK-NEXT: B t=95 n=10
// CHECK-NEXT: R n=10 w=59
// CHECK-NEXT: R n=10 w=59
// CHECK-NEXT: F t=105 a=30
// CHECK-NEXT: A t=135 n=14 a=39
// CHECK-NEXT: B t=135 n=14
// CHECK-NOT: {{.}}

