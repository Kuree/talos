// RUN: talos -emit-slang %s 2>&1 | FileCheck %s

module neg_setup(input wire c, d, output reg n = 0);
  timeunit 1ns; timeprecision 1ps;
  specify $setuphold(posedge c, d, -2, 5, n, 1'b0, 1'b1); endspecify
endmodule

module neg_hold(input wire c, d, output reg n = 0);
  timeunit 1ns; timeprecision 1ps;
  specify $setuphold(posedge c, d, 5, -2, n, 1'b0, 1'b1); endspecify
endmodule

module top;
  timeunit 1ns; timeprecision 1ps;
  logic c, d;
  wire n0, n1;
  neg_setup s(c, d, n0);
  neg_hold h(c, d, n1);
endmodule

// IEEE 1800-2023 31.9.2: a negative setup limit makes the data signal
// transition second, so the timecheck condition (argument 6) guards it and the
// timestamp condition (argument 5) guards the reference.
// CHECK: timing_check_arg_condition_children = array<i64: 5, 6, -1
// A negative hold limit swaps the pairing.
// CHECK: timing_check_arg_condition_children = array<i64: 6, 5, -1
