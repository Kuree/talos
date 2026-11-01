// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DWIDTH %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=WIDTH

// IEEE 1800-2023 31.9.1 Example 3: "CLK has only one delayed signal created for
// it", del_CLK, which the second check uses as well. A zero solved delay leaves
// del_DATA1 the original signal.
module top;
  timeunit 1ns; timeprecision 1ns;
  logic CLK = 0, DATA1 = 0, DATA2 = 0;
  reg n = 0;
`ifdef WIDTH
  wire [1:0] del_CLK;
`else
  wire del_CLK;
`endif
  wire del_DATA1;
  specify
    $setuphold(posedge CLK, DATA1, -10, 20, n, , , del_CLK, del_DATA1);
    $setuphold(posedge CLK, DATA2, -15, 18);
  endspecify
endmodule

// WIDTH: IEEE 1800-2023 31.9.1 delayed signal must have the width of the signal it delays

// CHECK-DAG: simulation.storage.decl [[CLK:[0-9]+]] in {{.*}}"__talos_negative_timing_delay_[[CLK]]" debug "implicit negative timing-check delayed signal"
// CHECK-DAG: simulation.driver.decl {{.*}}hierarchy "top.del_CLK" debug "continuous"
// CHECK-DAG: simulation.driver.decl {{.*}}hierarchy "top.del_DATA1" debug "continuous"
