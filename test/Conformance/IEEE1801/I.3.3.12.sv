// CLAUSE: Backward SAIF header example
// REQUIRES: upf
// XFAIL: *
// Talos has no SAIF writer or reader; --saif is the option this probe expects.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --saif=probe.saif -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.saif
// CHECK: {{^PASS$}}
// FILE0: (SAIFILE
// FILE0: (SAIFVERSION
// FILE0: (DIRECTION "backward")
// FILE0: (DESIGN
// FILE0: (DATE
// FILE0: (VENDOR
// FILE0: (PROGRAM_NAME
// FILE0: (VERSION
// FILE0: (DIVIDER
// FILE0: (TIMESCALE
// FILE0: (DURATION 20)

module top;
  logic q = 0;
  initial begin
    repeat (3) #5 q = ~q;
    #5 $display("PASS");
    $finish;
  end
endmodule
