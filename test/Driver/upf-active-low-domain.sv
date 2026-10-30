// REQUIRES: upf
// RUN: talos --upf %S/Inputs/upf/active-low.upf -O0 --mlir-verify-each %s -o %t.o0
// RUN: %t.o0 | FileCheck %s
// RUN: talos --upf %S/Inputs/upf/active-low.upf -O3 --mlir-verify-each %s -o %t.o3
// RUN: %t.o3 | FileCheck %s
// RUN: talos --upf %S/Inputs/upf/active-low.upf -O0 --execution-tier=bytecode %s -o %t.bc
// RUN: %t.bc | FileCheck %s
module upf_leaf(input logic d, output logic q);
  always_comb q = d;
endmodule
module upf_test;
  logic d = 0, power_en = 0, iso = 1;
  wire q;
  upf_leaf dut(d, q);
  initial begin
    #1;
    if (q !== 1'b0) $fatal(1, "negated switch should be powered at control zero");
    power_en = 1; iso = 0;
    #1;
    if (dut.q !== 1'bx || q !== 1'b1) $fatal(1, "active-low isolation failed");
    d = 1;
    #1;
    if (dut.q !== 1'bx) $fatal(1, "active-low OFF guard failed");
    power_en = 0; iso = 1;
    #1;
    if (q !== 1'b1) $fatal(1, "active-low power restoration failed");
    d = 0;
    #1 power_en = 1'bx;
    #1;
    if (dut.q !== 1'bx || q !== 1'bx) $fatal(1, "unknown switch control failed");
    power_en = 0;
    #1;
    if (q !== 1'b0) $fatal(1, "restoration from unknown switch failed");
    iso = 1'bx;
    #1;
    if (q !== 1'bx) $fatal(1, "unknown low-sense isolation failed");
    $display("active-low power and isolation passed");
    $finish;
  end
endmodule
// CHECK: active-low power and isolation passed
