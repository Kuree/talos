// CLAUSE: global sampled function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// v is 0 1 1 0 1 0 1. The past family is true on the tick it describes. The future family reads the next
// tick, so its attempt completes and reports there. A false future result is the assert's default failure.
// CHECK: PAST=0011010 ROSE=0100101 FELL=0001010 STABLE=1010000 CHANGED=0101111
// CHECK: FUTURE=0110101 RISING=0100101 FALLING=0001010 STEADY=0010000 CHANGING=0101111

module top;
  bit clk, v; int t;
  bit [0:6] V = 7'b0110101;
  bit [0:6] PAST, ROSE, FELL, STABLE, CHANGED, FUTURE, RISING, FALLING, STEADY, CHANGING;
  global clocking @(posedge clk); endclocking
  cover property (@($global_clock) $past_gclk(v)) PAST[t] = 1;
  cover property (@($global_clock) $rose_gclk(v)) ROSE[t] = 1;
  cover property (@($global_clock) $fell_gclk(v)) FELL[t] = 1;
  cover property (@($global_clock) $stable_gclk(v)) STABLE[t] = 1;
  cover property (@($global_clock) $changed_gclk(v)) CHANGED[t] = 1;
  assert property (@($global_clock) $future_gclk(v)) FUTURE[t] = 1; else ;
  assert property (@($global_clock) $rising_gclk(v)) RISING[t] = 1; else ;
  assert property (@($global_clock) $falling_gclk(v)) FALLING[t] = 1; else ;
  assert property (@($global_clock) $steady_gclk(v)) STEADY[t] = 1; else ;
  assert property (@($global_clock) $changing_gclk(v)) CHANGING[t] = 1; else ;
  initial begin
    for (t = 0; t < 7; t++) begin
      v = V[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("PAST=%b ROSE=%b FELL=%b STABLE=%b CHANGED=%b", PAST, ROSE, FELL, STABLE, CHANGED);
    $display("FUTURE=%b RISING=%b FALLING=%b STEADY=%b CHANGING=%b", FUTURE, RISING, FALLING, STEADY, CHANGING);
  end
endmodule
