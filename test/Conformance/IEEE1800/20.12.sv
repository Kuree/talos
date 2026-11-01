// CLAUSE: sampled past
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.12: s is 0 1 1 0 0 1 at ticks 0..5; ticks 1..5 give 2 rises (1,5), 1 fall (3), 2 stable (2,4), 3 changes (1,3,5), and $past(s,2)==1 at ticks 3,4.
// CHECK: rose=2 fell=1 stable=2 changed=3 past2=2

module top;
  bit clk, s;  int t;  int nf, rose, fell, stable, changed, past2;
  bit [0:5] S = 6'b011001;
  assert property (@(posedge clk) t > 0 && $rose(s)) rose++; else nf++;
  assert property (@(posedge clk) t > 0 && $fell(s)) fell++; else nf++;
  assert property (@(posedge clk) t > 0 && $stable(s)) stable++; else nf++;
  assert property (@(posedge clk) t > 0 && $changed(s)) changed++; else nf++;
  assert property (@(posedge clk) t > 0 && $past(s, 2) == 1) past2++; else nf++;
  initial begin
    for (t = 0; t < 6; t++) begin s = S[t]; #1 clk = 1; #1 clk = 0; end
    #1; $display("rose=%0d fell=%0d stable=%0d changed=%0d past2=%0d", rose, fell, stable, changed, past2);
  end
endmodule
