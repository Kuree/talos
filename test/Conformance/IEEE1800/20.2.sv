// CLAUSE: finish final
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.2: $finish ends the simulation at the call time (the t=10 process never runs) and final blocks run once.
// CHECK: EARLY t=5
// CHECK: FINAL t=5 hits=2
// CHECK-NOT: LATE
// CHECK-NOT: AFTER_FINISH

module top;
  int hits;
  initial begin #5; $display("EARLY t=%0t", $time); $finish(1); $display("AFTER_FINISH"); end
  initial begin #10; $display("LATE"); end
  always #2 hits++;
  final $display("FINAL t=%0t hits=%0d", $time, hits);
endmodule
