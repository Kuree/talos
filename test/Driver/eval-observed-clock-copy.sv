// RUN: talos -O3 --vpi=off --native-scheduler=eval --mlir-timing %s -o %t 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

module top;
  logic clk = 0, copy_clk;
  logic direct_data, copy_data, direct_expected, copy_expected;
  int direct_hits, copy_hits, failures;
  always #5 clk = !clk;
  assign copy_clk = clk;
  direct_history: assert property (@(posedge clk)
      $past(direct_data) === direct_expected)
    direct_hits++; else failures++;
  copy_history: assert property (@(posedge copy_clk)
      $past(copy_data) === copy_expected)
    copy_hits++; else failures++;
  initial begin
    // An uninitialized static logic variable has X as its default sampled
    // value (1800-2023 16.5.1). Set each input before the first clock.
    #1 direct_data = 0;
    copy_data = 1;
    #9 direct_expected = 0;
    copy_expected = 1;
    direct_data = 1;
    copy_data = 0;
    #10 $display("direct=%0d copy=%0d failures=%0d", direct_hits, copy_hits, failures);
    $finish;
  end
endmodule
// CHECK: direct=2 copy=2 failures=0
// PLAN: talos observed kernels: kernels=1 members=2
