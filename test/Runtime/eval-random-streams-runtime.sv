// RUN: %talos --std=1800-2023 -O3 -o %t %s
// RUN: %t | FileCheck %s

// Clocked draws in the generated eval executor. Expected values come from the C
// source in IEEE 1800-2023 Annex N.2. One process owns the global $random stream
// here, and its X route and known route draw exactly once per activation.
module sub #(parameter int SEED = 7) (input logic clk, input logic [7:0] d,
                                      output int value);
  int seed = SEED;
  logic [7:0] q;
  always_ff @(posedge clk) begin
    q <= d;
    value <= $dist_uniform(seed, 0, 100);
  end
endmodule

module eval_random_streams_runtime;
  logic clk = 0;
  logic [7:0] known;
  int explicit_seed = 42, normal_seed = 7, value[2];
  int first[4], second[4], first_count = 0, second_count = 0, left, right;
  always #5 clk = ~clk;

  always_ff @(posedge clk) begin
    automatic int draw = $random;
    if (known[0] === 1'bx)
      $display("x-route %08x", draw);
    else
      $display("known-route %08x", draw);
  end
  // CHECK-DAG: x-route 12153524
  // CHECK-DAG: x-route c0895e81
  // CHECK-DAG: known-route 8484d609
  // CHECK-DAG: known-route b1f05663

  // 20.14.1, 20.14.2: the seed is an inout argument and fully determines the
  // sequence.
  always_ff @(posedge clk) begin
    automatic int draw = $random(explicit_seed);
    $display("explicit %08x next=%0d", draw, explicit_seed);
  end
  // CHECK-DAG: explicit 802c4400 next=2900899
  // CHECK-DAG: explicit 2684734d next=-1501269880
  always_ff @(posedge clk) begin
    automatic int draw = $dist_normal(normal_seed, 100, 15);
    $display("normal %0d", draw);
  end
  // CHECK-DAG: normal 117
  // CHECK-DAG: normal 91

  // Instances share code and may fuse, but each has its own seed variable. Both
  // follow the same sequence, across their X and known input periods.
  for (genvar i = 0; i < 2; i++)
    sub instance_i(.clk, .d(known), .value(value[i]));
  always @(negedge clk) $display("uniform %0d %0d", value[0], value[1]);
  // CHECK-DAG: uniform 0 0
  // CHECK-DAG: uniform 78 78
  // CHECK-DAG: uniform 68 68

  // 18.14.2 thread locality: identically seeded threads return one sequence,
  // however their draws interleave. A shared stream would break the equality.
  always @(posedge clk) begin
    if (first_count == 0)
      process::self().srandom(100);
    if (first_count < 4)
      first[first_count] = $urandom;
    first_count = first_count + 1;
  end
  always @(posedge clk) begin
    if (second_count == 0)
      process::self().srandom(100);
    if (second_count < 4) begin
      second[second_count] = $urandom;
      second[second_count + 1] = $urandom;
    end
    second_count = second_count + 2;
  end
  // 18.14.1: each static process has its own stream.
  always_ff @(posedge clk) left <= $urandom;
  always_ff @(posedge clk) right <= $urandom;

  initial begin
    #22 known = 8'd3;
    #26;
    if (first == second)
      $display("thread locality holds");
    if (left != right)
      $display("thread streams differ");
    $finish;
  end
  // CHECK-DAG: thread locality holds
  // CHECK-DAG: thread streams differ
endmodule
