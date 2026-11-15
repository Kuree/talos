// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt --lower-talos-to-sim=opt-level=0 | FileCheck %s --check-prefix=PLAN
// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s --check-prefix=RUNTIME
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.3, 18.8 and 20.9: a live $countones target is compared
// with one shared prefix sum instead of enumerating every possible count. The
// SAMP header of the live CountPlan solve (65 random bits 'A', three captures)
// is bound by its node count: the low byte, then a high byte below 0x10 means
// fewer than 4096 nodes, so an enumeration of all 66 cardinalities cannot
// return unnoticed.
// PLAN: simulation.random.solve{{.*}}SAMP\01\00\00\00{{(\\[0-9A-Fa-f]{2}|[^"\\])}}\0{{[0-9A-Fa-f]}}\00\00\01\00\00\00A\00\00\00\03\00\00\00

// Equality and inequality cover zero, singleton, central and full counts,
// their neighbors, the signed targets -1 and 66 that no input satisfies, and
// frozen inputs. The companion test covers joint, truncated and wide targets.
// RUNTIME: linear count plans valid 1

class CountPlan;
  rand bit [64:0] value;
  int wanted;
  bit exclude;
  constraint relation {
    if (exclude) $countones(value) != wanted;
    else $countones(value) == wanted;
  }
endclass

module top;
  CountPlan c = new;
  bit good = 1;
  bit [64:0] previous;
  int status;
  int targets[11] = '{-1, 0, 1, 2, 31, 32, 33, 63, 64, 65, 66};
  initial begin
    // Both sides of each cardinality boundary exercise the same relation
    // without rebuilding an exact diagram for every interior count.
    foreach (targets[index]) begin
      int k;
      k = targets[index];
      c.wanted = k;
      c.exclude = 0;
      previous = c.value;
      status = c.randomize();
      good &= status == (k >= 0 && k <= 65);
      if (status) good &= $countones(c.value) == k;
      else good &= c.value == previous;
      c.exclude = 1;
      status = c.randomize();
      good &= status && $countones(c.value) != k;
    end
    c.exclude = 0;
    c.value = '1;
    c.value.rand_mode(0);
    c.wanted = 64;
    good &= !c.randomize() && c.value == '1;
    c.wanted = 65;
    good &= c.randomize() && c.value == '1;
    c.value.rand_mode(1);
    $display("linear count plans valid %0d", good);
    if (!good) $fatal(1, "linear count plan violation");
    $finish;
  end
endmodule
