// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DVARIABLE %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=VARIABLE
// RUN: talos -emit-slang -DREAD %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=VARIABLE

// IEEE 1800-2023 16.10, F.6.1: what a sequence of fixed length assigns to a local
// output one tick before its end point flows out of `.triggered` as the expression's
// value one tick ago, recorded by a sampler on the clock whichever ticks the monitor
// reaches the assignment on. A monitor reading an end point resumes after the
// Observed region, where end points are detected (16.13.6).
module top;
  bit clk, a, b;
  int d, q;
`ifdef VARIABLE
  // More than one attempt can end on a tick here, with a value each.
  sequence source(local output int x); @(posedge clk) (a, x = d) ##[1:2] b; endsequence
`elsif READ
  // The sequence reads the local, which is not design state.
  sequence source(local output int x); @(posedge clk) (a, x = d) ##1 b && x == q; endsequence
`else
  sequence source(local output int x); @(posedge clk) (a, x = d) ##1 b; endsequence
`endif
  property p;
    int v;
    source(v).triggered ##1 q == v;
  endproperty
  cover property (@(posedge clk) p) $display("covered");
endmodule

// VARIABLE: error: sequence event controls with local variables are not executable by the bounded endpoint monitor

// The end point waits on the clock and fires the event without local state.
// CHECK: simulation.func private @unit_{{[0-9]+}}(
// CHECK: simulation.suspend.edge posedge {{.*}}resume_region = 8
// CHECK: simulation.event.trigger

// The sampler records `d` on every tick, at the end of the time step.
// CHECK: simulation.func private @[[MONITOR:unit_[0-9]+]].$clocked_sample
// CHECK: simulation.suspend.edge posedge {{.*}}resume_region = 16
// CHECK: simulation.assert.clocked_sample_update

// The cover monitor runs in the Reactive region and reads the end point.
// CHECK: simulation.func private @[[MONITOR]](
// CHECK: simulation.suspend.edge posedge {{.*}}resume_region = 10
// CHECK: simulation.event.triggered
