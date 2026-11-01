// CLAUSE: Initial, always, final, fork and process control run in order; a delay in always_comb is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// CHECK: 1 status WAITING{{$}}
// CHECK-NEXT: 2 status KILLED{{$}}
// CHECK-NEXT: 3 disabled{{$}}
// CHECK-NEXT: 5 event{{$}}
// CHECK-NEXT: 15 wait{{$}}
// CHECK-NEXT: final count=2{{$}}

// Clause 9: each process-control form changes a time or a status that the probe prints.
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0;
  int count = 0;
  event ev;
  process p;
  always #5 clk = ~clk;
  always @(posedge clk) count++;
  final $display("final count=%0d", count);
  initial begin
    fork
      begin
        p = process::self();
        #100 $display("not reached");
      end
    join_none
    #1 $display("%0t status %s", $time, p.status().name());
    p.kill();
    #1 $display("%0t status %s", $time, p.status().name());
    fork : named
      #3 $display("%0t not reached", $time);
      #1 disable named;
    join
    $display("%0t disabled", $time);
    fork
      #2 ->ev;
      @ev $display("%0t event", $time);
    join
    wait (count == 2);
    $display("%0t wait", $time);
    $finish;
  end
endmodule
