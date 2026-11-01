// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 %s -o sim && ./sim | FileCheck %s --check-prefix=OUT
// RUN: FileCheck %s --check-prefix=FIRST < %t/first.log
// RUN: FileCheck %s --check-prefix=SECOND < %t/second.log

// IEEE 1800-2023 D.7: a log file copies standard output while enabled, and a new
// name closes the old file. Standard output itself is unaffected.
module top;
  initial begin
    $display("before");
    $log("first.log");
    $display("one");
    $nolog;
    $display("paused");
    $log;
    $display("two");
    $log("second.log");
    $display("three");
    $finish;
  end
endmodule

// OUT: before
// OUT: one
// OUT: paused
// OUT: two
// OUT: three
// FIRST-NOT: before
// FIRST-NOT: paused
// FIRST: one
// FIRST-NOT: paused
// FIRST: two
// FIRST-NOT: three
// SECOND-NOT: two
// SECOND: three
