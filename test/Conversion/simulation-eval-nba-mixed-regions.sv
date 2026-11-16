// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.5, 10.4.2, 11.5.1, 24.3.1: the program's four
// updates retain NBA form in the Reactive owner. Fusion must also retain the
// module's four writes to that shared root; only the private sibling capture
// may become an NBA-equivalent store.
// CHECK: simulation.func private @{{unit_[0-9]+}}({{.*}}home_region = 10 : i32{{.*}}simulation.hierarchical_name = "top.p"
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }}}
// CHECK-LABEL: simulation.func private @{{__talos_clocked_[0-9_]+}}(
// CHECK-SAME: home_region = 2 : i32
// CHECK: simulation.suspend.edge posedge
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK: simulation.ref.store %{{.*}} to %{{.*}} {schedule.eval.nba_equivalent_store}
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }}}
//
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic [1:0] mode = 0;
  logic signed [63:0] idx = 0;
  logic [7:0] q = 'x, r = 0;
  nba_region_program p();
  always #5 clk = !clk;
  always @(posedge clk) begin
    case (mode)
      0: q[idx +: 2] <= 0;
      1: q <= 8'ha5;
      2: q <= 8'h3c;
      3: q[idx +: 2] <= 0;
    endcase
  end
  always @(posedge clk) r <= q;
  initial begin
    #6; mode = 1;
    #10; mode = 2;
    #10; mode = 3; idx = 'x;
    #10; $display("%b %b", q, r);
    $finish;
  end
endmodule

program nba_region_program;
  initial forever begin
    @(posedge top.clk);
    case (top.mode)
      0: top.q[6 +: 2] <= 0;
      1: top.q[0 +: 2] <= 2'bzz;
      2: top.q[2 +: 2] <= 0;
      3: top.q <= 8'hf0;
    endcase
  end
endprogram
