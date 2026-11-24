// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.eval
// RUN: %t.eval | FileCheck %s
// RUN: talos -emit-slang --two-state %s | talos-opt --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{native.two_state}"},test-talos-native-backend{scheduler=eval sim-opt-level=3})' --mlir-print-ir-after=prepare-native-fragments,materialize-native-processes -o /dev/null 2> %t.fragments
// RUN: FileCheck %s --check-prefix=SLICE < %t.fragments
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval +define+WATCH_PAYLOAD %s -o %t.watched
// RUN: %t.watched | FileCheck %s --check-prefix=WATCH
// RUN: talos -emit-slang --two-state +define+WATCH_PAYLOAD %s | talos-opt --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{native.two_state}"},test-talos-native-backend{scheduler=eval sim-opt-level=3})' --mlir-print-ir-after=prepare-native-fragments -o /dev/null 2> %t.watched.fragments
// RUN: FileCheck %s --check-prefix=WATCH-IR < %t.watched.fragments

// The handoff between the two combinational processes keeps their frames
// live. The indexed part-select crosses a byte, then crosses either end of
// the packed root. Only in-range bits change (IEEE 1800-2023 11.5.1).
module top;
  bit clk, left_enable, right_enable;
  int ticks, falling_edges;
  logic left, right, seen_left, seen_right;
  logic [129:0] payload;
  int offset;
  logic [7:0] data;

  always #5 clk = !clk;
  always_ff @(posedge clk) ticks <= ticks + 1;
  always_comb begin
    seen_right = right;
    payload[offset +: 8] = data;
    left = 0;
    left = left_enable;
  end
  always_comb begin
    seen_left = left;
    right = 0;
    right = right_enable;
  end
  always @(negedge left or negedge right) falling_edges++;
`ifdef WATCH_PAYLOAD
  int rises, changes;
  always @(payload[7]) changes++;
  always @(posedge payload[7]) rises++;
`endif

  initial begin
    #1 data = 8'hf0;
    #1 left_enable = 1;
    offset = 7;
    data = 8'ha5;
    #5 $display("middle=%h neighbor=%h observed=%b ticks=%0d",
                payload[14:7], payload[6:0], seen_left, ticks);
    left_enable = 0;
    right_enable = 1;
    offset = 128;
    data = 8'h03;
    #2 offset = 150;
    data = 0;
    #2 offset = -2;
    data = 8'hb4;
    #2 $display("high=%h middle=%h low=%h seen=%b edges=%0d",
                payload[129:128], payload[14:7], payload[5:0], seen_right, falling_edges);
`ifdef WATCH_PAYLOAD
    // Write a new slice value with bit 7 still high, then pulse the bit.
    offset = 7;
    data = 8'ha7;
    #1 data = 8'ha6;
    #1 data = 8'ha7;
    #1 $display("rises=%0d changes=%0d", rises, changes);
`endif
    $finish;
  end
endmodule
// CHECK: middle=a5 neighbor=70 observed=1 ticks=1
// CHECK: high=3 middle=a5 low=2d seen=1 edges=1
// WATCH: rises=2 changes=3
// SLICE: simulation.func private @[[WRITER:unit_[0-9]+]]({{.*}}native.ranked_signal_writer
// SLICE: %[[LAST:.*]] = llvm.mlir.constant(122 : i64)
// SLICE-NEXT: %[[IN:.*]] = arith.cmpi ule, %{{.*}}, %[[LAST]]
// SLICE-NEXT: cf.cond_br %[[IN]], ^[[FAST:bb[0-9]+]], ^[[SLOW:bb[0-9]+]]
// SLICE: ^[[FAST]]:
// SLICE: schedule.state.store {{.*}}, @__talos_state_value
// SLICE: ^[[SLOW]]:
// SLICE: schedule.state.frame_store {{.*}} to %{{.*}} continuous
// SLICE: IR Dump After MaterializeNativeProcessesPass
// SLICE: llvm.func @[[WRITER]].__talos_coro_ramp(
// SLICE: %[[VCHANGE:.*]] = arith.cmpi ne, {{.*}} : i64
// SLICE-NEXT: %[[XCHANGE:.*]] = arith.cmpi ne, {{.*}} : i64
// SLICE-NEXT: %[[CHANGED:.*]] = arith.ori %[[VCHANGE]], %[[XCHANGE]]
// SLICE-NEXT: cf.cond_br %[[CHANGED]], ^[[PUBLISH:bb[0-9]+]], ^[[JOIN:bb[0-9]+]]
// SLICE: ^[[PUBLISH]]:
// SLICE: schedule.transition {{.*}} width = 1 : i64
// SLICE-NEXT: cf.br ^[[JOIN]]
// WATCH-IR: simulation.func private @{{unit_[0-9]+}}({{.*}}native.ranked_signal_writer
// WATCH-IR-NOT: llvm.mlir.constant(122 : i64)
// WATCH-IR: schedule.state.frame_store {{.*}} continuous
// WATCH-IR-NOT: llvm.mlir.constant(122 : i64)
// WATCH-IR: {{^    [}]$}}
