// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=TWICE
// RUN: talos -emit-slang -DSAMPLED %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=SAMPLED
// RUN: talos -emit-slang -DPARTIAL %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=PARTIAL
// RUN: talos --coverage=toggle -emit-slang -DSAMPLED %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=TOGGLE
// RUN: talos -emit-slang -DCHAIN %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=CHAIN
// RUN: talos -emit-slang -DCASCADE %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=CASCADE
// RUN: talos -emit-slang -DCYCLE %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=CYCLE
// RUN: talos -emit-slang -DONCE %s | talos-opt --test-talos-native-backend='stop-after=graph' | FileCheck %s --check-prefix=ONCE

// Each clock, two NBAs write `c` and leave its value unchanged:
// c <= c + 1 and then c <= c are performed in that order (IEEE 1800-2023
// 4.6(b), 10.4.2), so c goes 1 -> 2 -> 1. Each change is an update event that
// schedules an evaluation of the always_comb sensitive to c (4.3, 4.5,
// 9.2.2.2.1). A merged commit acts as the permitted order in which both
// updates precede the evaluation (4.5, 4.7) and, with c unchanged, omits the
// evaluation. That is sound only if nothing can see an update event that the
// evaluation itself would produce.
//  - twice: the always_comb assigns y twice. With c[0] = 1 each evaluation
//    takes y from 1 to 0 and back to 1, and the 0 -> 1 update is a posedge
//    (9.4.2, Table 9-2) that wakes the counter. `c` must stay change-watched.
//  - sampled: the same glitch, but no process is sensitive to y; a flop only
//    samples it. The evaluation may run without suspension (4.7), so the flop
//    reads y before or after it and never sees the glitch. `c` may merge.
//  - toggle: the sampled design with toggle coverage on everything but c.
//    Coverage counts every transition of y, so `c` stays change-watched.
//  - chain: a watcher of y copies it with its own default-then-override
//    assignment, and an edge waits on that copy. The glitch passes through
//    the watcher, so `c` stays change-watched.
//  - cascade: the same glitch, watched only by another always_comb that
//    copies y once. Woken with an unchanged final y, it assigns the value it
//    already holds, so the glitch stops there and `c` may merge.
//  - cycle: two always_combs each assign twice an output the other watches.
//    Neither can be shown skippable before the other, so neither is, and `c`
//    stays change-watched.
//  - partial: z is cleared and then z[1] is assigned again, so bit 1 of z
//    can pass through another value, and a process waits on z. `c` stays
//    change-watched.
//  - once: every bit of y and z is assigned exactly once, including disjoint
//    bit-selects of z, although processes wait on both. An evaluation with
//    unchanged inputs assigns the values already held, which is no change in
//    state (4.3), so `c` may merge.
// Storage ids follow declaration order: clk=0, c=1, y=2, z=3, q=4, n=5,
// m=6, w=7.

// TWICE-LABEL: simulation.design @design
// TWICE-SAME: schedule.nba.change_watched = array<i64: 1>
// TWICE-SAME: schedule.nba.transient_observable = array<i64: 0, 2>

// SAMPLED-LABEL: simulation.design @design
// SAMPLED-SAME: schedule.nba.change_watched = array<i64>
// SAMPLED-SAME: schedule.nba.transient_observable = array<i64: 0>

// TOGGLE-LABEL: simulation.design @design
// TOGGLE-SAME: schedule.nba.change_watched = array<i64: 1>
// TOGGLE-SAME: schedule.nba.transient_observable = array<i64: 0, 2, 3, 4, 5, 6, 7>

// CHAIN-LABEL: simulation.design @design
// CHAIN-SAME: schedule.nba.change_watched = array<i64: 1, 2>
// CHAIN-SAME: schedule.nba.transient_observable = array<i64: 0, 7>

// CASCADE-LABEL: simulation.design @design
// CASCADE-SAME: schedule.nba.change_watched = array<i64>
// CASCADE-SAME: schedule.nba.transient_observable = array<i64: 0>

// CYCLE-LABEL: simulation.design @design
// CYCLE-SAME: schedule.nba.change_watched = array<i64: 1, 2, 7>
// CYCLE-SAME: schedule.nba.transient_observable = array<i64: 0>

// PARTIAL-LABEL: simulation.design @design
// PARTIAL-SAME: schedule.nba.change_watched = array<i64: 1, 3>
// PARTIAL-SAME: schedule.nba.transient_observable = array<i64: 0>

// ONCE-LABEL: simulation.design @design
// ONCE-SAME: schedule.nba.change_watched = array<i64: 3>
// ONCE-SAME: schedule.nba.transient_observable = array<i64: 0, 2>

module nba_transient_observers_repeated_write;
  logic clk = 0;
  always #5 clk = ~clk;
  // talos coverage off toggle
  logic [7:0] c = 1;
  // talos coverage on toggle
  logic y;
  logic [1:0] z;
  logic q;
  int n = 0;
  int m = 0;
  logic w;

  always_comb begin
`ifdef ONCE
    y = c[0];
    z[0] = c[1];
    z[1] = c[2];
`elsif PARTIAL
    y = c[0];
    z = '0;
    z[1] = c[1];
`elsif CYCLE
    y = 1'b0;
    if (c[0] & w)
      y = 1'b1;
`else
    y = 1'b0;
    if (c[0])
      y = 1'b1;
`endif
  end

`ifdef SAMPLED
  always_ff @(posedge clk) q <= y;
`elsif PARTIAL
  always @(z) m = m + 1;
`elsif CHAIN
  always_comb begin
    w = 1'b0;
    if (y)
      w = 1'b1;
  end
  always @(posedge w) n = n + 1;
`elsif CASCADE
  always_comb w = y;
`elsif CYCLE
  always_comb begin
    w = 1'b0;
    if (y)
      w = 1'b1;
  end
`elsif ONCE
  always @(posedge y) n = n + 1;
  always @(z) m = m + 1;
`else
  always @(posedge y) n = n + 1;
`endif

  always_ff @(posedge clk) begin
    c <= c + 1;
    c <= c;
  end
endmodule
