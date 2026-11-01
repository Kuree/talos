// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 timing=true' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE --implicit-check-not=operation=simulation.random.legacy --implicit-check-not=operation=simulation.random.distribution < %t.trace
// RUN: FileCheck %s < %t.mlir

// $random and $dist_* run Annex N on a global or explicit seed (IEEE 1800-2023
// 20.14) and name no thread, so they stay in the generated eval body, in
// statement order (4.6(a)). The other random constructs draw from the executing
// thread's stream (18.13.3, 18.14.1, 18.14.2), which only the runtime can
// select, so their bodies run at a runtime checkpoint.
module eval_random_streams;
  logic clk = 0;
  int first, second, seed = 7, ranged_seed = 9, uniform, seeded, thread, ranged;
  int restarted, randomized, shuffled[2] = '{1, 2};
  process holder;
  string state;
  always #5 clk = ~clk;

  always_ff @(posedge clk) begin
    first = $random;
    second = $random;
  end
  always_ff @(posedge clk) seeded <= $random(seed);
  always_ff @(posedge clk) uniform <= $dist_uniform(ranged_seed, 0, 100);

  always_ff @(posedge clk) thread <= $urandom;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.random.next source=loc("{{.*}}":[[# @LINE - 1]]:
  always_ff @(posedge clk) ranged <= $urandom_range(7);
  // TRACE-DAG: reason=runtime-state-access operation=simulation.random.bounded source=loc("{{.*}}":[[# @LINE - 1]]:
  always_ff @(posedge clk) restarted <= $urandom(254);
  // TRACE-DAG: reason=runtime-state-access operation=simulation.random.seed source=loc("{{.*}}":[[# @LINE - 1]]:
  always_ff @(posedge clk) void'(std::randomize(randomized));
  // TRACE-DAG: reason=runtime-state-access operation=simulation.random.state source=loc("{{.*}}":[[# @LINE - 1]]:
  always @(posedge clk) shuffled.shuffle();
  // TRACE-DAG: reason=runtime-state-access operation=simulation.random.bounded source=loc("{{.*}}":[[# @LINE - 1]]:
  always @(posedge clk) holder = process::self();
  // TRACE-DAG: reason=runtime-state-access operation=simulation.process.current source=loc("{{.*}}":[[# @LINE - 1]]:
  always @(negedge clk) if (holder != null) state = holder.get_randstate();
  // TRACE-DAG: reason=runtime-state-access operation=simulation.process.random_state source=loc("{{.*}}":[[# @LINE - 1]]:
  always @(negedge clk) if (holder != null) holder.srandom(55);
  // TRACE-DAG: reason=runtime-state-access operation=simulation.process.set_random_state source=loc("{{.*}}":[[# @LINE - 1]]:
endmodule

// The $random unit and the fused kernel holding both explicit-seed draws stay
// generated; every thread-stream body is a checkpoint.
// TRACE: talos eval executor inventory: tier1=2 tier2=0 runtime_checkpoints=8

// CHECK-LABEL: llvm.func @__talos_fused_0_0.__talos_eval_body_0(
// CHECK-COUNT-2: llvm.call @talos_rt_v1_random_distribution(%arg0,
// CHECK-LABEL: llvm.func @unit_5.__talos_eval_body_0(
// Neither result is read, yet each call still advances the global stream.
// CHECK-COUNT-2: llvm.call @talos_rt_v1_random_legacy(%arg0,
// CHECK: llvm.return
