// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt --lower-talos-to-sim=opt-level=0 | FileCheck %s --check-prefix=PLAN
// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s --check-prefix=RUNTIME
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.3, 18.8 and 20.9: joint random counts, a three-bit
// truncation of the sum, and 130-bit targets whose high bits must not alias
// a legal count. Each operation must retain its compiled sampling plan.
// PLAN-COUNT-3: simulation.random.solve{{(_wide)?}} {{.*}}SAMP
// RUNTIME: joint truncated and wide count plans valid 1

class JointPlan;
  rand bit [7:0] value;
  rand int count;
  constraint relation { count == $countones(value); }
endclass

class TruncatedPlan;
  rand bit [64:0] value;
  bit [2:0] wanted;
  constraint relation { 3'($countones(value)) == wanted; }
endclass

class WidePlan;
  rand bit [12:0] value;
  bit [129:0] wanted;
  constraint relation { $countones(value) == wanted; }
endclass

module top;
  JointPlan j = new;
  TruncatedPlan t = new;
  WidePlan w = new;
  bit good = 1;
  initial begin
    for (int k = 0; k < 16; k++) begin
      good &= j.randomize() && j.count == $countones(j.value);
      t.wanted = k[2:0];
      good &= t.randomize() && 3'($countones(t.value)) == t.wanted;
      w.wanted = k % 14;
      good &= w.randomize() && $countones(w.value) == w.wanted;
    end
    w.wanted = 130'h1 << 100;
    good &= !w.randomize();
    w.wanted = '1;
    good &= !w.randomize();
    w.wanted = 13;
    good &= w.randomize() && w.value == '1;
    $display("joint truncated and wide count plans valid %0d", good);
    if (!good) $fatal(1, "joint count plan violation");
    $finish;
  end
endmodule
