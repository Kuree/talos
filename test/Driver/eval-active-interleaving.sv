// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.eval
// RUN: %t.eval > %t.out
// RUN: FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=generic %s -o %t.generic
// RUN: %t.generic | diff -u %t.out -
//
// The comb processes publish intermediate zeroes even when their final
// values stay high. Their Active-region interleaving and the rearm after
// the copied input settles must make progress (1800-2023 4.7, 9.4.2).
module top;
  bit clk, enable, select_bit;
  int ticks;
  logic request, select_out, feedback, observed;
  wire forwarded = ~select_out;

  always #5 clk = !clk;
  always_ff @(posedge clk) ticks <= ticks + 1;

  always_comb begin
    request = 0;
    select_out = 0;
    observed = forwarded;
    if (enable) request = 1;
    if (feedback && select_bit) select_out = 1;
  end
  always_comb begin
    feedback = 0;
    if (request || select_bit) feedback = 1;
  end

  initial begin
    #2 enable = 1;
    select_bit = 1;
    #5 $display("on %b%b%b%b ticks=%0d", request, select_out, feedback, observed, ticks);
    select_bit = 0;
    enable = 0;
    #10 $display("off %b%b%b%b ticks=%0d", request, select_out, feedback, observed, ticks);
    $finish;
  end
endmodule
// CHECK: on 1110 ticks=1
// CHECK: off 0001 ticks=2
