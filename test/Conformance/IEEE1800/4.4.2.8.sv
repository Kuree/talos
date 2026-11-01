// CLAUSE: program reactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.4.2.8: a program NBA lands in Re-NBA, after the Reactive and Re-Inactive events (b stays 0 across the display and #0).
// CHECK: R1 b=0
// CHECK: R2 b=0
// CHECK: R3 b=0
// CHECK: R4 b=1

module top;
  int a, b;
  initial begin #1; a <= 1; end                 // module NBA at t=1
  program p;
    initial begin
      #1;
      $display("R1 b=%0d", b);
      b <= 1;                                   // Re-NBA
      $display("R2 b=%0d", b);
      #0; $display("R3 b=%0d", b);              // Re-Inactive: still old
      #1; $display("R4 b=%0d", b);
    end
  endprogram
endmodule
