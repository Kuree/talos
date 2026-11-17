// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t 2> %t.diag | FileCheck %s
// RUN: FileCheck %s --check-prefix=DIAG < %t.diag

// A partial island with a shared runtime calendar. The reset sequence's final
// wait and the last initial's one-shot waits run once (IEEE 1800-2023 9.2.1)
// as runtime owners while the generated loop owns the clock; each must still
// observe its own edge (9.4.2).

module native_periodic_reset_tail_island;
  logic clk = 0;
  logic rst_n = 0;
  logic [7:0] cnt;
  logic [7:0] twice;
  logic hit = 0;
  int seen = 0;
  initial forever #5 clk = ~clk;
  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  end
  always @(posedge clk)
    if (!rst_n) cnt <= 0;
    else cnt <= cnt + 1;
  assign twice = cnt << 1;
  initial begin
    @(negedge clk);
    @(posedge cnt[2]);
    hit = 1;
    seen = cnt;
  end
  initial begin
    #200;
    $display("cnt=%0d twice=%0d rst_n=%b hit=%0d seen=%0d", cnt, twice, rst_n,
             hit, seen);
    $finish;
  end
endmodule

// CHECK: cnt=17 twice=34 rst_n=1 hit=1 seen=4
// DIAG: talos-signal-diagnostics
// DIAG-SAME: periodic_preparations={{[1-9][0-9]*}}
