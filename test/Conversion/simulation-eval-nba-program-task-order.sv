// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=lowering' | FileCheck %s
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --check-prefix=BACKEND --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.6(b), 10.4.2, 24.3.1: retain the program's Reactive
// owner and the task-call continuation before its next NBA. The caller's
// update cannot move ahead of the task call, and the task keeps its captured
// input as the RHS of its NBA to module storage.
// CHECK: simulation.func private @{{unit_[0-9]+}}({{.*}}home_region = 10 : i32{{.*}}simulation.hierarchical_name = "top.p"
// CHECK-NOT: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.task.call @[[TASK:unit_[0-9]+]]({{.*}}) arguments 2 to ^[[RESUME:bb[0-9]+]]
// CHECK-NEXT: ^[[RESUME]]:
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue
// CHECK-NOT: simulation.ref.store
// CHECK: {{^    }}}
// CHECK: simulation.func private @[[TASK]](
// CHECK-SAME: %[[VALUE:arg[0-9]+]]: !simulation.packed_array<7 : 0 x !simulation.logic<1>>
// CHECK: %[[DEST:.*]] = simulation.context.storage %{{.*}}[1]
// CHECK-NEXT: simulation.nba.enqueue %[[VALUE]] to %[[DEST]]
// CHECK: simulation.return
//
// BACKEND-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic [7:0] q = 0, r = 0;
  nba_task_program p();
  always #5 clk = !clk;
  always @(posedge clk) r <= q;
  task automatic put(input logic [7:0] value);
    q <= value;
  endtask
endmodule

program nba_task_program;
  initial forever begin
    @(posedge top.clk);
    top.put(8'h3c);
    top.q <= 8'ha5;
  end
endprogram
