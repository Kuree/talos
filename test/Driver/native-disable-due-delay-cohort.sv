// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// IEEE 1800-2023 9.6.2: disabling a named block that another process is
// executing resumes that process after the block; it runs before the
// disabler's nonblocking assignment takes effect (4.5: the NBA region follows
// the Active region). Here the target waits on a delay that is due in the same
// time slot as more than 16 other delays, so it sits in the scheduler's cached
// ready cohort (two-tier B2 S2) when it is disabled; the cohort must not keep
// its stale ordering key.
module native_disable_due_delay_cohort;
  logic x = 0;
  initial begin
    #10 disable target.blk;
    x <= 1;
    $display("%0t disabler done", $time);
    #100;
  end
  for (genvar i = 0; i < 40; i++) begin : g
    initial begin
      #(10 + 10 * (i >= 3 && i <= 7))
      $display("%0t filler %0d",
               $time,
               i);
      #100;
    end
  end
  initial begin : target
    begin : blk
      #10 $display("%0t target inside (WRONG)", $time);
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
