// RUN: talos --two-state -O0 -emit-sim %s | FileCheck %s --check-prefix=IR
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref > %t.ref.out && FileCheck %s --check-prefix=FOUR < %t.ref.out
// RUN: talos -O3 --vpi=off %s -o %t.native && %t.native | diff -u %t.ref.out -
// RUN: talos --two-state -O0 --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 > %t.two.out && FileCheck %s --check-prefix=TWO < %t.two.out
// RUN: talos --two-state -O3 --vpi=off %s -o %t.native2 && %t.native2 | diff -u %t.two.out -

// IEEE 1800-2023 9.4.2 and 11.5.1. Changing a runtime index can change
// the primary even when neither stored bit is written at that time. A fixed
// index can use a direct event, but its value follows the execution domain.
// IR: %[[HIGH:[a-zA-Z0-9_]+]] = simulation.ref.subelement %{{[a-zA-Z0-9_]+}}{{\[\[0\]\]}}
// IR: simulation.suspend.change %[[HIGH]] to
// IR: %[[ONE:[a-zA-Z0-9_]+]] = simulation.ref.subelement %{{[a-zA-Z0-9_]+}}{{\[\[5\]\]}}
// IR: simulation.suspend.change %[[ONE]] to
// IR: simulation.suspend.observe
// FOUR: counts 2 2 4
// TWO: counts 2 0 4
module top #(parameter int Width = 7);
  logic [Width-1:0] bus = '0;
  int fixedCount, domainCount, dynamicCount;
  int idx = 0;
  always @(bus[Width-1]) fixedCount++;
  always @(bus[(1'bx === 1'b0) ? 1 : 0]) domainCount++;
  always @(bus[idx]) dynamicCount++;
  initial begin
    #1 bus[0] = 1;
    #1 idx = 1;
    #1 bus[Width-1] = 1;
    #1 idx = Width-1;
    #1 bus[Width-1] = 0;
    #1 bus[0] = 0;
    #1 $display("counts %0d %0d %0d", fixedCount, domainCount, dynamicCount);
    $finish;
  end
endmodule
