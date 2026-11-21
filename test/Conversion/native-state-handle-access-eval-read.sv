// RUN: talos -emit-slang %s | not talos-opt --test-talos-native-backend='scheduler=eval' --mlir-print-ir-after=prepare-native-fragments --mlir-print-ir-after=materialize-native-processes -o /dev/null 2>&1 | FileCheck %s

// The leaf's register reads an input port bound to an array element that the
// initial block forces, so its generated eval body reads the port behind the
// static specialization guard, through the runtime: native lowering reads the
// state the handle names as a scalar value. AOT planning reads that access by
// its plane, width and handle and replaces its value with a clamped read of
// the canonical plane, which keeps the value of an invalid index for the bits
// outside the root (IEEE 1800-2023 11.5.1); no runtime call or temporary is
// left.
// The guard itself still leaves the eval call closure, so the driver compiles
// this design again with the generic scheduler
// (Driver/generic-scheduler-fallback.sv).
module leaf(input var logic clk, input var logic [3:0] d,
            output var logic [3:0] q);
  always_ff @(posedge clk) q <= d;
endmodule

module top;
  logic clk = 0;
  logic [3:0] data[2] = '{1, 5};
  logic [3:0] result[2];
  leaf u(clk, data[1], result[0]);
  always #5 clk = ~clk;
  initial begin
    #6 force u.d = 4'ha;
    #10 release u.d;
  end
endmodule

// CHECK-LABEL: IR Dump After PrepareNativeFragmentsPass
// CHECK-LABEL: simulation.func private @unit_2.__talos_eval_body_0(
// CHECK: %[[LOADED:[0-9]+]] = schedule.state.load_handle @__talos_state_value[%{{.*}}] {state_bits = {{[0-9]+}} : i64} : i4
// CHECK-NEXT: cf.br ^{{bb[0-9]+}}(%[[LOADED]] : i4)

// CHECK-LABEL: IR Dump After MaterializeNativeProcessesPass
// CHECK-LABEL: func.func private @unit_2.__talos_eval_body_0(
// CHECK-NOT: llvm.alloca
// CHECK: schedule.state.load @__talos_state_value[%{{.*}}] {alignment = 1 : i64} : i16
// CHECK-NOT: schedule.state.load_handle
// CHECK-NOT: llvm.call
// CHECK-NOT: llvm.intr.lifetime.start
// CHECK: %[[SELECTED:[0-9]+]] = arith.ori %{{.*}}, %{{.*}} : i4
// CHECK-NEXT: cf.br ^{{bb[0-9]+}}(%[[SELECTED]] : i4)

// CHECK: error: generated eval hot closure calls runtime symbol talos_rt_v1_static_specialization_guard
