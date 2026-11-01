// RUN: talos --no-negative-timing-checks -O0 -emit-sim %s 2>&1 | FileCheck %s
// RUN: talos -O0 -emit-sim %s 2>&1 | FileCheck %s --check-prefix=ON

module neg_cell(input wire c, d, output reg q = 0);
  timeunit 1ns; timeprecision 1ps;
  wire dc, dd;
  reg n = 0;
  always @(posedge dc) q <= dd;
  specify $setuphold(posedge c, d, -2, 5, n, , , dc, dd); endspecify
endmodule

module top;
  timeunit 1ns; timeprecision 1ps;
  logic c = 0, d = 0;
  wire q;
  neg_cell dut(c, d, q);
endmodule

// IEEE 1800-2023 31.9.4: the option is recorded on the module, the delayed
// reference and data signals join the nets of the originals, and the negative
// setup limit bounds nothing.
// CHECK: simulation.no_negative_timing_checks
// CHECK: simulation.net.connect.decl 0 in {{[0-9]+}} 1[0] to 3[0] width 1 reversed = false provenance "alias"
// CHECK: simulation.net.connect.decl 1 in {{[0-9]+}} 2[0] to 4[0] width 1 reversed = false provenance "alias"
// CHECK: simulation.timing_check_arg_ticks = array<i64: 0, 0, 0, 5000,
// With negative checks on, the delayed signals have drivers of the delayed copies.
// ON-DAG: simulation.driver.decl {{.*}}hierarchy "top.dut.dc"
// ON-DAG: simulation.driver.decl {{.*}}hierarchy "top.dut.dd"
