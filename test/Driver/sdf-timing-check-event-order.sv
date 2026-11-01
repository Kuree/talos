// RUN: cd %S && talos -emit-slang %s 2>&1 | FileCheck %s

`timescale 1ns / 1ps

// SDF SETUP, HOLD and SETUPHOLD name the data event first. RECOVERY, REMOVAL
// and RECREM name the control signal first and NOCHANGE the clock, which is the
// SystemVerilog reference event of those checks (IEEE 1800-2023 31.3.4-31.3.6,
// 31.4.6). Each check needs the events in its own order to match (Table 32-2).
module sdf_order_cell(input wire r, s, c, d, output logic n);
  specify
    $recovery(posedge r, posedge c, 1, n);
    $removal(posedge r, posedge c, 1, n);
    $recrem(posedge s, posedge c, 1, 1, n);
    $nochange(posedge c, d, 1, 1, n);
    $hold(posedge c, d, 1, n);
    $setup(d, posedge c, 1, n);
  endspecify
endmodule

module sdf_order_top;
  logic r, s, c, d;
  wire n;
  sdf_order_cell dut(r, s, c, d, n);
  initial $sdf_annotate("Inputs/sdf-timing-check-event-order.sdf");
endmodule

// CHECK-NOT: warning: {{.*}}SDF
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 2000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 3000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 4000000, 5000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 6000000, 7000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 8000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 9000000, 0>
