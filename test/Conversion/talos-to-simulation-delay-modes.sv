// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos | FileCheck %s

`timescale 1ns / 100ps

// IEEE 1800-2023 E.4 to E.7 name the modes. Every mode is pinned on the same
// module: a continuous assignment, a gate, a net and a path, all with delays.
`delay_mode_path
module mode_path(input a, output y, z); wire #3 n = a; assign #5 y = a; buf #4 (z, a);
  specify (a => y) = 2; endspecify endmodule
`delay_mode_distributed
module mode_distributed(input a, output y, z); wire #3 n = a; assign #5 y = a; buf #4 (z, a);
  specify (a => y) = 2; endspecify endmodule
`delay_mode_unit
module mode_unit(input a, output y, z); wire #3 n = a; assign #5 y = a; buf #4 (z, a);
  specify (a => y) = 2; endspecify endmodule
`delay_mode_zero
module mode_zero(input a, output y, z); wire #3 n = a; assign #5 y = a; buf #4 (z, a);
  specify (a => y) = 2; endspecify endmodule
`resetall
`timescale 1ns / 100ps
module mode_none(input a, output y, z); wire #3 n = a; assign #5 y = a; buf #4 (z, a);
  specify (a => y) = 2; endspecify endmodule
module top; logic a; wire [4:0] y, z;
  mode_path p(a, y[0], z[0]); mode_distributed d(a, y[1], z[1]);
  mode_unit u(a, y[2], z[2]); mode_zero o(a, y[3], z[3]); mode_none v(a, y[4], z[4]);
endmodule

// Path mode drops the distributed delays and keeps the path.
// CHECK: hierarchical_name = "top.p.n"
// CHECK-NOT: delay_fs
// CHECK: talos.sv.symbol.timing_path {{.*}}timing_delay_fs = array<i64: 2000000>
// Distributed mode keeps the distributed delays and drops the path.
// CHECK: talos.sv.symbol.net {{.*}}delay_fs = array<i64: 3000000>{{.*}}"top.d.n"
// CHECK: talos.sv.symbol.continuous_assign {{.*}}delay_fs = array<i64: 5000000>
// CHECK: talos.sv.symbol.primitive_instance {{.*}}delay_fs = array<i64: 4000000>
// CHECK: talos.sv.symbol.timing_path {{.*}}timing_delay_fs = array<i64: 0>
// Unit mode makes each nonzero distributed delay one precision step.
// CHECK: talos.sv.symbol.net {{.*}}delay_fs = array<i64: 100000>{{.*}}"top.u.n"
// CHECK: talos.sv.symbol.continuous_assign {{.*}}delay_fs = array<i64: 100000>
// CHECK: talos.sv.symbol.primitive_instance {{.*}}delay_fs = array<i64: 100000>
// CHECK: talos.sv.symbol.timing_path {{.*}}timing_delay_fs = array<i64: 0>
// Zero mode has no delay at all.
// CHECK: hierarchical_name = "top.o.n"
// CHECK-NOT: delay_fs
// CHECK: talos.sv.symbol.timing_path {{.*}}timing_delay_fs = array<i64: 0>
// With no directive every delay stays.
// CHECK: talos.sv.symbol.net {{.*}}delay_fs = array<i64: 3000000>{{.*}}"top.v.n"
// CHECK: talos.sv.symbol.continuous_assign {{.*}}delay_fs = array<i64: 5000000>
// CHECK: talos.sv.symbol.primitive_instance {{.*}}delay_fs = array<i64: 4000000>
// CHECK: talos.sv.symbol.timing_path {{.*}}timing_delay_fs = array<i64: 2000000>
