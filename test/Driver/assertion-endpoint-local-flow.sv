// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 --execution-tier=native %s -o native && ./native | FileCheck %s
// RUN: cd %t && talos -O0 --execution-tier=bytecode %s -o bytecode && ./bytecode | FileCheck %s

// IEEE 1800-2023 F.6.1, with a = 1001 0000, b = 0100 1000 and d = 5 and 6 at ticks 0
// and 3. The end points are at ticks 1 and 4, carrying 5 and 6 out through v, and q
// matches the first one on the next tick and the second two ticks later, which only
// fixed delays of the source reach.
module top;
  bit clk, slow, a, b; int d, q, t;
  bit [0:7] A = 8'b10010000, B = 8'b01001000, SLOW = 8'b00011011;
  int D[8] = '{5, 0, 0, 6, 0, 0, 0, 0};
  int Q[8] = '{0, 0, 5, 0, 0, 0, 6, 0};
  bit [0:7] TRIGGERED, MATCHED, NEXT, LATER, PAST;
  sequence plain; @(posedge clk) a ##1 b; endsequence
  sequence flow(local output int x); @(posedge clk) (a, x = d) ##1 b; endsequence
  property next; int v; flow(v).triggered ##1 q == v; endproperty
  property later; int v; flow(v).triggered ##2 q == v; endproperty
  // 16.9.3: $past counts ticks of the clock, not how often this monitor reaches the
  // item. `b` holds on ticks 1 and 4 only, and d was 5 and 6 the tick before.
  property past; int v; (b, v = $past(d)) ##1 v inside {5, 6}; endproperty
  // Each monitor of one Observed region sees an end point of that tick, whichever
  // order they run in (16.13.6). All of these read it, ahead of `next` or not.
  cover property (@(posedge clk) plain.triggered) TRIGGERED[t] = 1;
  cover property (@(posedge slow) plain.matched) MATCHED[t] = 1;
  cover property (@(posedge clk) next) NEXT[t] = 1;
  cover property (@(posedge clk) later) LATER[t] = 1;
  cover property (@(posedge clk) past) PAST[t] = 1;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t]; d = D[t]; q = Q[t];
      #1 slow = SLOW[t];
      #1 slow = 0; clk = 1;
      #1 clk = 0;
      #1;
    end
    $display("T=%b M=%b N=%b L=%b P=%b", TRIGGERED, MATCHED, NEXT, LATER, PAST);
  end
endmodule
// CHECK: T=01001000 M=00010010 N=00100000 L=00000010 P=00100100
