// RUN: cd %S && talos -emit-slang %s 2>&1 | FileCheck %s

`timescale 1ns / 1ps

module sdf_kinds_cell(input wire a, d, c, output wire y, output logic n);
  specparam T = 1;
  specify
    (a => y) = 4;
    $setuphold(posedge c, d, 1, 1, n);
  endspecify
  assign y = a;
  initial #T n = 1;
endmodule

module sdf_kinds_sink(input wire i);
endmodule

module sdf_kinds_top;
  logic a, d, c;
  wire y, n;
  sdf_kinds_cell dut(a, d, c, y, n);
  sdf_kinds_sink sink(y);
  initial $sdf_annotate("Inputs/sdf-annotation-kinds.sdf");
endmodule

// LABEL (32.4.3) changes the specparam value.
// CHECK: slang.symbol.specparam {{.*}}constant_value = "5"
// PATHPULSE (30.7.3) reject 0.5 ns and error 1 ns replace the defaults.
// CHECK: sdf_pulse_error_fs = 1000000 : i64
// CHECK-SAME: sdf_pulse_reject_fs = 500000 : i64
// SDF SETUPHOLD (Table 32-2) replaces the $setuphold limits 1 ns and 1 ns
// with 4 ns and -2 ns; the notifier slot is unchanged.
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 4000000, -2000000, 0>
// A use of the annotated specparam is marked so its fold is recomputed.
// CHECK: sdf_annotated_specparam
// INTERCONNECT (32.4.4) keeps the load connection as a delayed driver.
// CHECK: sdf_interconnect
// CHECK: slang.symbol.net {{.*}}delay_fs = array<i64: 3000000, 3000000, 3000000>
