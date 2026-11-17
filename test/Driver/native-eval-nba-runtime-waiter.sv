// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t 2> %t.diag | FileCheck %s
// RUN: FileCheck %s --check-prefix=DIAG < %t.diag

// `count` changes only by an NBA update, which is an update event for every
// process sensitive to it (IEEE 1800-2023 4.5, 10.4.2, 9.4.2). Two waiters
// have no generated ready bit: an initial repeat loop, which stays a
// runtime-owned finite bootstrap, and a program's Reactive initial (24.3).
// The generated NBA barrier must hand both wakes to the runtime, also for a
// root wider than 64 bits. The program's end is the implicit $finish (24.7);
// the final block reports.
module native_eval_nba_runtime_waiter;
  logic clk = 0;
  logic rst_n = 0;
  int count = 0;
  logic [127:0] wide = 0;
  logic hit_initial = 0, hit_program = 0, hit_wide = 0;
  initial forever #5 clk = ~clk;
  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1;
  end
  always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0;
    else count <= count + 1;
  always @(posedge clk) wide <= wide + {64'd1, 64'd1};
  initial begin
    #100;
    repeat (2) @(posedge count[0]);
    hit_initial = 1;
  end
  initial begin
    #100;
    repeat (2) @(posedge wide[64]);
    hit_wide = 1;
  end
  initial #300 $finish;
  final
    $display("t=%0t count=%0d initial=%b program=%b wide=%b", $time, count,
             hit_initial, hit_program, hit_wide);
  waiter u_waiter();
endmodule

program waiter;
  initial begin
    #100;
    @(posedge native_eval_nba_runtime_waiter.count[2]);
    native_eval_nba_runtime_waiter.hit_program = 1;
  end
endprogram

// CHECK: t=135 count=12 initial=1 program=1 wide=1
// DIAG: talos-signal-diagnostics
// DIAG-SAME: eval_dispatches={{[1-9][0-9]*}}
