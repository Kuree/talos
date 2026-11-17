// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t 2> %t.diag | FileCheck %s
// RUN: FileCheck %s --check-prefix=DIAG < %t.diag

// The reset sequence's final wait is reached once (IEEE 1800-2023 9.2.1), so
// the periodic preparation drains it before the generated loop owns the
// clock. The string-appending process is a runtime checkpoint that fires on
// every edge of that prefix; the bootstrap must resume through it without
// losing the reset sequence's wake (9.4.2), then hand the clock over. The
// last initial reaches its once-only clock wait after the handoff.
module native_periodic_reset_tail;
  logic clk = 0;
  logic rst_n = 0;
  int count = 0;
  int doubled;
  string log_s = "";
  logic late = 0;
  initial forever #5 clk = ~clk;
  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  end
  assign doubled = count * 2;
  always @(posedge clk) if (count < 4) log_s = {log_s, "x"};
  always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0;
    else count <= count + 1;
  initial begin
    #100;
    @(negedge clk);
    late = 1;
  end
  initial begin
    #200;
    $display("count=%0d doubled=%0d len=%0d late=%b", count, doubled,
             log_s.len(), late);
    $finish;
  end
endmodule

// CHECK: count=17 doubled=34 len=7 late=1
// DIAG: talos-signal-diagnostics
// DIAG-SAME: aot_checkpoints={{[1-9][0-9]*}}
// DIAG-SAME: eval_dispatches={{[1-9][0-9]*}}
// DIAG-SAME: periodic_preparations={{[1-9][0-9]*}}
