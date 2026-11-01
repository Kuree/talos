// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DEXPLICIT -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=BAD
// RUN: talos -DDEFAULTED -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=BAD

// IEEE 1800-2023 16.5.1: an input variable of a clocking block used in a
// concurrent assertion is sampled with #1step sampling, and any other sampling
// shall result in an error. Its default skew is #1step, and action blocks read
// current values rather than samples.
module top;
  bit clk, data, seen;
`ifdef EXPLICIT
  clocking cb @(posedge clk); input #0 data; endclocking
`elsif DEFAULTED
  clocking cb @(posedge clk); default input #2; input data; endclocking
`else
  clocking cb @(posedge clk); input #1step data; endclocking
`endif
  clocking other @(posedge clk); input #0 data; endclocking
  clocking implicit_step @(posedge clk); input data; endclocking
  // BAD: error: IEEE 1800-2023 16.5.1 requires a clocking block input used in a concurrent assertion to have #1step sampling
  a: assert property (@(posedge clk) cb.data && implicit_step.data)
    seen = other.data;
endmodule

// CHECK: simulation.assert.sampled_read
