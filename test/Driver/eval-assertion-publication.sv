// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t 2> %t.diag | FileCheck %s
// RUN: FileCheck %s --check-prefix=DIAG < %t.diag

// The disable pulse falls entirely between the antecedent at 15 and its
// consequent at 25. Its occurrence must cancel the attempt, including when
// both stores occur within one activation (1800-2023 16.12). The next
// attempt evaluates its Preponed sample in Observed and reports in Reactive.
module assertion_publication;
  bit clk, reset = 1, pulse, start;
  int count, failures;
  always #5 clk = !clk;
  always_ff @(posedge clk) count <= reset ? 0 : count + 1;
  assert property (@(posedge clk) disable iff (reset || pulse) start |=> 0)
    else failures++;
  initial begin
    #10 reset = 0;
    start = 1;
    #7 pulse = 1;
    pulse = 0;
    #3 start = 0;
    #10 start = 1;
    #10 start = 0;
    #11 $display("count=%0d failures=%0d", count, failures);
    $finish;
  end
endmodule

// CHECK: count=4 failures=1
// DIAG: eval_dispatches={{[1-9][0-9]*}}
