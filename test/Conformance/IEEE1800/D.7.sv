// CLAUSE: $log and $nolog optional interface
// XFAIL: *
// Optional Annex D interface; the compiler does not implement $log and $nolog.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=session.log
// Pins D.7: the log file holds the text printed while logging was enabled and not the text printed between $nolog and $log.
// CHECK: ENABLED
// CHECK: DISABLED
// CHECK: AGAIN
// FILE0: ENABLED
// FILE0-NOT: DISABLED
// FILE0: AGAIN

module top;
  initial begin
    $log("session.log");
    $display("ENABLED");
    $nolog;
    $display("DISABLED");
    $log;
    $display("AGAIN");
  end
endmodule
