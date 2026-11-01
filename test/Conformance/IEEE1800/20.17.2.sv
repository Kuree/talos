// CLAUSE: stacktrace
// XFAIL: *
// $stacktrace prints only the innermost frame (top.inner), not the calling task outer up to the top-level process (20.17.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.17.2: $stacktrace prints the call stack up to the top-level process, so both nested tasks appear.
// CHECK: BEGIN
// CHECK: inner
// CHECK: outer
// CHECK: END

module top;
  task automatic inner(); $stacktrace; endtask
  task automatic outer(); inner(); endtask
  initial begin
    $display("BEGIN");
    outer();
    $display("END");
  end
endmodule
