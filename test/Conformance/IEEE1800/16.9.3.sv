// CLAUSE: sampled past
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// v is 0 1 1 0 1 0. Before the first tick the past value is the default, so tick 0 is stable. $past(v,1,en)
// reads the last earlier tick with en true.
// CHECK: SAMPLED=011010 ROSE=010010 FELL=000101 STABLE=101000 CHANGED=010111
// CHECK: PAST=001101 PAST2=000110 GATED=000111

module top;
  bit clk, v, en; int t;
  bit [0:5] V = 6'b011010, EN = 6'b101011;
  bit [0:5] SAMPLED, ROSE, FELL, STABLE, CHANGED, PAST, PAST2, GATED;
  cover property (@(posedge clk) $sampled(v)) SAMPLED[t] = 1;
  cover property (@(posedge clk) $rose(v)) ROSE[t] = 1;
  cover property (@(posedge clk) $fell(v)) FELL[t] = 1;
  cover property (@(posedge clk) $stable(v)) STABLE[t] = 1;
  cover property (@(posedge clk) $changed(v)) CHANGED[t] = 1;
  cover property (@(posedge clk) $past(v)) PAST[t] = 1;
  cover property (@(posedge clk) $past(v, 2)) PAST2[t] = 1;
  cover property (@(posedge clk) $past(v, 1, en)) GATED[t] = 1;
  initial begin
    for (t = 0; t < 6; t++) begin
      v = V[t]; en = EN[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("SAMPLED=%b ROSE=%b FELL=%b STABLE=%b CHANGED=%b", SAMPLED, ROSE, FELL, STABLE, CHANGED);
    $display("PAST=%b PAST2=%b GATED=%b", PAST, PAST2, GATED);
  end
endmodule
