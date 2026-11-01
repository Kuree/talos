// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 %s -o sim && ./sim +run=7 | FileCheck %s

// IEEE 1800-2023 D.8: after $reset the simulation is at time 0 with variables at
// their initial values and procedures starting again. $reset_count counts the
// resets and $reset_value gives the last reset_value, and the plusargs persist.
module top;
  int v = 1;
  int run;
  initial begin
    if (!$value$plusargs("run=%d", run)) $fatal(1, "plusargs lost");
    $display("count=%0d value=%0d v=%0d t=%0t run=%0d", $reset_count, $reset_value, v, $time, run);
    v = 2;
    #5;
    if ($reset_count == 0)
      $reset(0, 42);
    if ($reset_count == 1)
      $reset(1, 43);
    $finish;
  end
endmodule

// CHECK: count=0 value=0 v=1 t=0 run=7
// CHECK: count=1 value=42 v=1 t=0 run=7
// CHECK: count=2 value=43 v=1 t=0 run=7
