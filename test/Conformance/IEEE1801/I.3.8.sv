// CLAUSE: Backward SAIF path-dependent toggle attributes
// REQUIRES: upf
// XFAIL: *
// Talos has no SAIF writer or reader; --saif is the option this probe expects.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --saif=probe.saif -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.saif
// CHECK: {{^PASS$}}
// FILE0: (IOPATH
// FILE0: (TC 3)

module top;
  logic q = 0;
  initial begin
    repeat (3) #5 q = ~q;
    #5 $display("PASS");
    $finish;
  end
endmodule
