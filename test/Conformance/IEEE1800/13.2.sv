// CLAUSE: Subroutines: functions complete in zero time, tasks may consume time
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 13.2: a function executes in zero time and returns one value; a task may consume time.
// CHECK: F r=8 dt=0
// CHECK: T q=7 dt=3

module top;
  function automatic int dbl(int x); return x * 2; endfunction
  task automatic wait3(output int r); #3; r = 7; endtask
  int f, q;  time t0, t1, t2;
  initial begin
    t0 = $time;  f = dbl(4);  t1 = $time;  wait3(q);  t2 = $time;
    $display("F r=%0d dt=%0d", f, t1 - t0);
    $display("T q=%0d dt=%0d", q, t2 - t1);
  end
endmodule
