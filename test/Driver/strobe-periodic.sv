// RUN: talos -O3 --mlir-timing %s -o %t 2> %t.timing
// RUN: FileCheck %s --check-prefix=PLAN < %t.timing
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.err
// RUN: FileCheck %s < %t.out
// RUN: FileCheck %s --check-prefix=DIAG < %t.err

// IEEE 1800-2023 21.2.2: starting a $strobe display is a cold runtime leaf of
// the strobing activation. The generated owner stays native and takes a
// checkpoint only in the activations that strobe, so the generated periodic
// loop keeps the clock on its own calendar: no shared-calendar drain in any
// slot. The display runs in the Postponed region (4.4.2.9) with the values at
// the end of the slot. The text is what every other tier prints.
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
// CHECK-NEXT: A t=95 n=10 a=27
// CHECK-NEXT: B t=95 n=10
// CHECK-NEXT: R n=10 w=59
// CHECK-NEXT: R n=10 w=59
// CHECK-NEXT: F t=105 a=30
// CHECK-NEXT: A t=135 n=14 a=39
// CHECK-NEXT: B t=135 n=14
// CHECK-NOT: {{.}}

// DIAG: talos-signal-diagnostics {{.*}}aot_checkpoints={{[1-9][0-9]*}} {{.*}}periodic_preparations={{[1-9][0-9]*}} {{.*}}periodic_slot_drains=0{{$}}

// Only the displays are withheld, as cold report evaluators; no owner runs at
// a runtime checkpoint.
// PLAN-NOT: dynamic spawn multiplicity
// PLAN: withheld actor: {{.*}} reason=postponed display
// PLAN-NOT: dynamic spawn multiplicity
// PLAN: talos eval executor inventory: tier1={{[1-9]}} tier2=0 runtime_checkpoints=0
