// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=generic sim-opt-level=0 stop-after=lowering' -o %t
// RUN: FileCheck %s --check-prefix=CUT < %t
// RUN: talos-opt %t --test-talos-simulation-schedule-analysis=preemptions=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=RANK

// IEEE 1800-2023 4.7, 9.4.2: the pulse cycle A <-> B is broken by a cut in
// A's body after its default writes. The continuous assignment q = ~x2 reads
// A's partial x2 and feeds A's prefix input x3. If it ran inside the handoff
// window it would publish from partial state, reach A while A is unarmed and
// re-trigger it forever. It is ranked after A's continuation instead: A
// completes and re-arms first, and only a net change re-triggers it.
// CUT-LABEL: simulation.func private @unit_1(
// CUT: simulation.suspend.delay %{{.*}} to ^{{bb[0-9]+}} {resume_region = 2 : i32, schedule.active_preemption_after = [@unit_2], site
// RANK-LABEL: schedule @design
// RANK: func @unit_0 entry={{[0-9]+}}
// RANK: bb1 rank=[[#PRODUCER:]]
// RANK: func @unit_1
// RANK: bb4 rank=[[#PRODUCER-1]]
// RANK: preemption @unit_1 ordered=1
module top;
  logic e, s, x1, x2, x3, y;
  wire q;
  assign q = ~x2;
  always_comb begin
    x1 = 1'b0;
    x2 = 1'b0;
    x3 = q;
    if (e) x1 = 1'b1;
    if (y & s) x2 = 1'b1;
  end
  always_comb begin
    y = 1'b0;
    if (x1 | s) y = 1'b1;
  end
endmodule
