// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t && %t > %t.out
// RUN: FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
//
// The same testbench frame changes between an edge wait and a #0 delay.
// Both activations read the old value. The following falling edge reads
// the NBA value and the completed Observed action (1800-2023 4.4, 4.5).
module top;
  bit clk;
  int q, observed;
  always #5 clk = !clk;
  always_ff @(posedge clk) q <= q + 1;
  a: assert property (@(posedge clk) q < 4) observed++;
  initial begin
    fork
      begin
        for (int i = 0; i < 4; ++i) begin
          @(posedge clk);
          if (q != i) $fatal(1, "Active q=%0d expected=%0d", q, i);
          #0;
          if (q != i) $fatal(1, "Inactive q=%0d expected=%0d", q, i);
        end
      end
      begin
        for (int i = 1; i <= 4; ++i) begin
          @(negedge clk);
          if (q != i || observed != i)
            $fatal(1, "after NBA q=%0d observed=%0d expected=%0d", q, observed, i);
        end
      end
    join
    $display("q=%0d observed=%0d", q, observed);
    $finish;
  end
endmodule
// CHECK: q=4 observed=4
