// RUN: cd %S && talos -emit-slang %s 2>%t.err | FileCheck %s
// RUN: FileCheck %s --check-prefix=WARN < %t.err

`timescale 1ns / 1ps

// IEEE 1800-2023 32.4.1, 32.4.2, Tables 32-1 to 32-3: a construct's condition and
// edge have to match those of the declaration it annotates, so each declaration
// below has one that differs only there and keeps its source value.
module sdf_match_cell(input wire a, b, c, d, r, s, mode, m2, net_load, port_load,
                      inout wire inout_load, output wire v, w, y, z, output reg n);
  specparam T = 1;
  assign v = b;
  assign w = a;
  assign y = a;
  assign z = a;
  specify
    if (s) (a => y) = 1;
    if (!s) (a => y) = 2;
    if (s) (a => z) = 3;
    ifnone (a => z) = 4;
    (a => w) = 11;
    (b => w) = 12;
    (b => v) = T + 2;
    // SETUPHOLD COND picks by condition, and an edge has to match as well.
    $setuphold(posedge c &&& mode, d, 1, 1, n);
    $setuphold(negedge c &&& mode, d, 1, 1, n);
    // The transition set is what matches, with z as x (31.5).
    $setup(d, edge [01] c, 1, n);
    $setup(d, edge [10] c, 1, n);
    $hold(edge [10] c, d, 1, n);
    $recovery(edge [0x] r, posedge c, 1, n);
    // SCOND and CCOND match the timestamp and timecheck conditions.
    $recrem(r, posedge c, 1, 1, n, s, !m2);
    $recrem(r, posedge c, 1, 1, n, m2, s);
  endspecify
endmodule

module sdf_match_top;
  logic a, b, c, d, r, s, mode, m2;
  wire net_load, port_load, inout_load, v, w, y, z, n;
  sdf_match_cell dut(a, b, c, d, r, s, mode, m2, net_load, port_load, inout_load,
                     v, w, y, z, n);
  initial $sdf_annotate("Inputs/sdf-matching.sdf");
endmodule

// The !mode SETUPHOLD matches no declaration here.
// WARN: Inputs/sdf-matching.sdf:15:{{[0-9]+}}: warning: SDF TIMINGCHECK did not match a timing check
// An inout's net carries signals both ways.
// WARN: Inputs/sdf-matching.sdf:{{[0-9]+}}:{{[0-9]+}}: warning: SDF interconnect delay to an inout module port is not applied

// LABEL reevaluates the path delay T + 2 (32.4.3). DEVICE w reaches both paths
// to w and no other. PATHPULSEPERCENT stays a percentage of each transition.
// CHECK: slang.symbol.net {{.*}}delay_fs = array<i64: 3000000, 3000000, 3000000>{{.*}}hierarchical_name = "sdf_match_top.dut.net_load"
// CHECK: slang.symbol.net {{.*}}delay_fs = array<i64: 4000000, 4000000, 4000000>{{.*}}hierarchical_name = "sdf_match_top.dut.port_load"
// CHECK-NOT: delay_fs{{.*}}inout_load
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 5000000>
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 7000000>
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 3000000>
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 9000000>
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 6000000>
// CHECK: slang.symbol.timing_path {{.*}}delay_fs = array<i64: 6000000>
// CHECK: slang.symbol.timing_path {{.*}}sdf_pulse_error_millipercent = 50000{{.*}}sdf_pulse_reject_millipercent = 20000{{.*}}delay_fs = array<i64: 10000000>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 2000000, 3000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 1000000, 1000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 4000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 1000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 5000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 6000000, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 7000000, 8000000, 0, 0, 0>
// CHECK: timing_check_arg_time_fs = array<i64: 0, 0, 1000000, 1000000, 0, 0, 0>
