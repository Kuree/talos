// CLAUSE: sequence triggered
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// e1 ends at clk ticks 1 and 4. triggered is true from Observed to the end of that time step only, so a wait wakes
// there and the falling edge reads false. matched persists to the next tick of the slower clock.
// A reader also sees the end point of a clock a program drives, in the Reactive region.
// CHECK: PROGRAM CLOCK 3
// CHECK: SEEN=00100100 WAITED=01001000 AFTER=00000000 MATCHED=00010010

program driver;
  initial begin
    top.pa = 1;
    #1 top.pclk = 1;
    #1 top.pclk = 0;
    top.pa = 0; top.pb = 1;
    #1 top.pclk = 1;
    #1 top.pclk = 0;
    // The end of a program would end the simulation (24.7).
    #100;
  end
endprogram

module top;
  bit pclk, pa, pb;
  sequence e2; @(posedge pclk) pa ##1 pb; endsequence
  cover property (@(posedge pclk) e2.triggered) $display("PROGRAM CLOCK %0t", $time);
  driver d();
  bit clk, slow, a, b, c; int t;
  bit [0:7] A = 8'b10010000, B = 8'b01001000, C = 8'b00100100, SLOW = 8'b00011011;
  bit [0:7] SEEN, WAITED, AFTER, MATCHED;
  sequence e1; @(posedge clk) a ##1 b; endsequence
  cover property (@(posedge clk) e1.triggered ##1 c) SEEN[t] = 1;
  cover property (@(posedge slow) e1.matched) MATCHED[t] = 1;
  initial forever begin
    wait (e1.triggered);
    WAITED[t] = 1;
    @(negedge clk);
  end
  always @(negedge clk) AFTER[t] = e1.triggered;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 slow = SLOW[t];
      #1 slow = 0; clk = 1;
      #1 clk = 0;
      #1;
    end
    $display("SEEN=%b WAITED=%b AFTER=%b MATCHED=%b", SEEN, WAITED, AFTER, MATCHED);
    $finish;
  end
endmodule
