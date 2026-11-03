// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// One process suspends on a different conditional wait each time: edge waits
// with an `iff` guard (IEEE 1800-2023 9.4.2.3: the guard is evaluated when the
// event operand changes) and level waits (9.4.3). Each suspension registers
// its own event operand and drops the previous one (two-tier B2 S6), so a
// change of an operand the process no longer waits on must not wake it, and a
// change of the current one must.

module native_conditional_wait_alternation;
  logic a = 0, b = 0, en = 1, lv = 0;
  logic [31 : 0] v = 0;
  integer hits = 0;
  // One process alternating between two different iff waits and a level wait.
  initial
    forever begin
      @(posedge a iff en) begin
        hits++;
        $display("%0t A", $time);
      end
      @(posedge b iff en) begin
        hits++;
        $display("%0t B", $time);
      end
      wait(lv) begin
        hits++;
        $display("%0t L", $time);
      end
      @(posedge v[17] iff en) begin
        hits++;
        $display("%0t V17", $time);
      end
      wait(v[5]) begin
        hits++;
        $display("%0t V5", $time);
      end
    end
  initial begin
    #1 a = 1;
    #1 a = 0;
    #1 b = 1;
    #1 b = 0;
    #1 a = 1;
    #1 a = 0; // must be ignored (waiting on lv)
    #1 lv = 1;
    #1 v = 32'h0002_0000; // posedge v[17]
    #1 v = 32'h0000_0000;
    #1 v = 32'h0000_0020; // v[5]
    #1 lv = 0;
    a = 1;    // A again
    #1 b = 1; // B
    #1 v = 0;
    #1 lv = 1;            // L
    #1 v = 32'h0002_0000; // V17
    #1 v = 32'h0002_0020; // V5
    #1 $display("hits=%0d", hits);
    $finish;
  end
endmodule

// CHECK: 1 A
// CHECK-NEXT: 3 B
// CHECK-NEXT: 7 L
// CHECK-NEXT: 8 V17
// CHECK-NEXT: 10 V5
// CHECK-NEXT: 11 A
// CHECK-NEXT: 12 B
// CHECK-NEXT: 14 L
// CHECK-NEXT: 15 V17
// CHECK-NEXT: 16 V5
// CHECK-NEXT: hits=10
