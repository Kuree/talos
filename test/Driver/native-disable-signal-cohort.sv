// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// IEEE 1800-2023 9.6.2, 4.5: as for a delay cohort, a process woken by an
// edge together with more than 16 others sits in the cached ready cohort; a
// disable from a cohort member resumes it after its block before the
// disabler's nonblocking assignment takes effect.
module native_disable_signal_cohort;
  logic clk = 0;
  logic x = 0;
  initial
    #10 clk = 1;
  initial begin
    @(posedge clk) disable target.blk;
    x <= 1;
    $display("%0t disabler done", $time);
  end
  for (genvar i = 0; i < 40; i++) begin : g
    initial @(posedge clk)
      $display("%0t filler %0d", $time, i);
  end
  initial begin : target
    begin : blk
      @(posedge clk) $display("%0t target inside (WRONG)",
                              $time);
    end
    $display("%0t target after blk x=%0d", $time, x);
  end
  initial
    #30 $display("%0t end", $time);

  // CHECK: 10 disabler done
  // CHECK-NEXT: 10 target after blk x=0
  // CHECK-NOT: WRONG
  // CHECK: 30 end
endmodule
