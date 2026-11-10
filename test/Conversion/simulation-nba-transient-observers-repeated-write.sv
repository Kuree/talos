// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=TWICE
// RUN: talos -emit-slang -DONCE %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=ONCE
// RUN: talos -emit-slang -DPARTIAL %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=TWICE

// Each clock, two NBAs write `c` and leave its value unchanged:
// c <= c + 1 and then c <= c are performed in that order (IEEE 1800-2023
// 4.6(b), 10.4.2), so c goes 1 -> 2 -> 1. Each change is an update event that
// schedules an evaluation of the always_comb sensitive to c (4.3, 4.5,
// 9.2.2.2.1). A merged commit acts as the permitted order in which both
// updates precede the evaluation (4.5, 4.7) and, with c unchanged, omits the
// evaluation. That is sound only if the evaluation itself produces no update
// event.
//  - twice: the always_comb assigns y twice. With c[0] = 1 each evaluation
//    takes y from 1 to 0 and back to 1, and the 0 -> 1 update is a posedge
//    (9.4.2, Table 9-2) that wakes the counter. `c` must stay change-watched.
//  - partial: z is cleared and then z[1] is assigned again, so bit 1 of z
//    can pass through another value. `c` stays change-watched.
//  - once: every bit of y and z is assigned exactly once, including disjoint
//    bit-selects of z. An evaluation with unchanged inputs assigns the values
//    already held, which is no change in state (4.3), so `c` may merge.
// Storage ids follow declaration order: clk=0, c=1, y=2, z=3, n=4.

// TWICE-LABEL: simulation.design @design
// TWICE-SAME: schedule.nba.change_watched = array<i64: 1>
// TWICE-SAME: schedule.nba.transient_observable = array<i64: 0, 2>

// ONCE-LABEL: simulation.design @design
// ONCE-SAME: schedule.nba.change_watched = array<i64>
// ONCE-SAME: schedule.nba.transient_observable = array<i64: 0, 2>

module nba_transient_observers_repeated_write;
  logic clk = 0;
  always #5 clk = ~clk;
  logic [7:0] c = 1;
  logic y;
  logic [1:0] z;
  int n = 0;

  always_comb begin
`ifdef ONCE
    y = c[0];
    z[0] = c[1];
    z[1] = c[2];
`elsif PARTIAL
    y = c[0];
    z = '0;
    z[1] = c[1];
`else
    y = 1'b0;
    if (c[0])
      y = 1'b1;
`endif
  end

  always @(posedge y) n = n + 1;

  always_ff @(posedge clk) begin
    c <= c + 1;
    c <= c;
  end
endmodule
