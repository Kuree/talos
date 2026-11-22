// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3' | FileCheck %s

// IEEE 1800-2023 4.5, 4.6(b), 4.7: the posedge kernel stores `q`, the wide
// `wq` and the array element `mem[a]` directly, which performs their NBA
// updates early; `s`, which an always_comb $display observes, keeps its NBA.
// The evaluations an NBA update causes may run after every update of its NBA
// region, so the wakes of every direct store, narrow, wider than a machine
// word, or at a dynamic index, wait in the held set. The coordinator merges
// them after the commit applies `s`, so each always_comb runs once per edge,
// not before and after the commit. Edges are still decided at the store
// (9.4.2).
module top;
  bit clk; always #5 clk = ~clk;
  logic [7:0] q = 0, s = 0, w, v, acc = 0;
  logic [64:0] wq = 0;
  logic [7:0] mem [4] = '{default: 0};
  logic [1:0] a = 0;
  always_comb begin
    case (q[1:0])
      0: w = q + s;
      1: w = q - s;
      2: w = q ^ s;
      default: w = q & s;
    endcase
  end
  always_comb v = wq[64:57] + mem[a] + s;
  always_ff @(posedge clk) q <= q + 1;
  always_ff @(posedge clk) wq <= {wq[63:0], wq[64]} + 1;
  always_ff @(posedge clk) begin mem[a] <= mem[a] + 1; a <= a + 1; end
  always_ff @(posedge clk) s <= s + 3;
  always_comb if (s == 8'd99) $display("s=%0d", s);
  always_ff @(negedge clk) acc <= acc + w + v;
  initial begin #3000 $display("%h", acc); $finish; end
endmodule

// The held set is a second ready set in the ingress layout; it lists the leaf
// words a held publication can reach.
// CHECK: llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1() {{.*}}schedule.eval.nba_held_words = array<i32: 0>} : !llvm.array<1 x i64>
// No direct store of the kernel publishes into the ingress set or through
// the runtime: each wake is the same ready update, into the held set.
// CHECK-LABEL: llvm.func {{.*}}@__talos_clocked_0_1_0.__talos_eval_body_0(
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK-NOT: transition
// CHECK: %[[HELD:.+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK-NOT: transition
// CHECK: %[[OLD:.+]] = llvm.load %[[HELD]] {alignment = 8 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: %[[NEW:.+]] = llvm.or %[[OLD]], %{{.+}}
// CHECK-NEXT: llvm.store %[[NEW]], %[[HELD]]
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK-NOT: transition
// CHECK: {{^  }}llvm.func
// schedule_run merges them right before it hands the time slot back to the
// runtime (and before each return).
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: %[[RHELD:.+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK: %[[RPEND:.+]] = llvm.load %[[RHELD]]
// CHECK-NEXT: %[[RANY:.+]] = llvm.icmp "ne" %[[RPEND]]
// CHECK-NEXT: llvm.cond_br %[[RANY]], ^[[RMERGE:bb[0-9]+]], ^[[HANDOFF:bb[0-9]+]](
// CHECK-NEXT: ^[[HANDOFF]](
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_handoff_periodic_aot
// CHECK: ^[[RMERGE]]:
// CHECK-NEXT: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: llvm.br ^[[HANDOFF]](
// A one-word layout has no summaries or cache: the merge moves the word.
// CHECK-LABEL: llvm.func internal @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: %[[ZERO:.+]] = llvm.mlir.constant(0 : i64)
// CHECK-NEXT: %[[HELD:.+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NEXT: %[[INGRESS:.+]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[WAKES:.+]] = llvm.load %[[HELD]]
// CHECK-NEXT: %[[READY:.+]] = llvm.load %[[INGRESS]]
// CHECK-NEXT: %[[MERGED:.+]] = llvm.or %[[READY]], %[[WAKES]]
// CHECK-NEXT: llvm.store %[[MERGED]], %[[INGRESS]]
// CHECK-NEXT: llvm.store %[[ZERO]], %[[HELD]]
// CHECK-NEXT: llvm.return
// The coordinator merges the held set into the ingress set in five places,
// each gated by a test of the held set. At quiescence with nothing staged the
// wakes merge and dispatch at once; after the commit they merge before the
// post-NBA ingress test; and before each return (complete, stopped, failed),
// so the held set is empty whenever the runtime runs.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK-DAG: %[[INGRESS:.+]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-DAG: %[[DHELD:.+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: llvm.br ^[[DISPATCH:bb[0-9]+]]{{$}}
// CHECK: llvm.call @__talos_eval_four_state_nba_handoff_v1(
// CHECK: ^[[POSTNBA:bb[0-9]+]]:  //
// CHECK-NEXT: %[[POST:.+]] = llvm.load %[[INGRESS]]
// CHECK-NEXT: %[[EMPTY:.+]] = llvm.icmp "eq" %[[POST]]
// CHECK-NEXT: llvm.cond_br %[[EMPTY]], ^{{bb[0-9]+}}(%{{.+}} : i32), ^[[DISPATCH]]{{$}}
// CHECK-NEXT: ^{{bb[0-9]+}}:  // pred:
// CHECK-NEXT: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: llvm.br ^[[POSTNBA]]{{$}}
// CHECK-COUNT-3: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK-NOT: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK: llvm.func {{.*}}@__talos_eval_four_state_nba_handoff_v1
