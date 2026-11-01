// CLAUSE: Backward SAIF net, port, and leakage-switching specifications
// REQUIRES: upf
// XFAIL: *
// Talos has no SAIF writer or reader; --saif is the option this probe expects.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --saif=probe.saif -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.saif
// CHECK: {{^PASS$}}
// FILE0: (NET
// FILE0: (PORT
// FILE0: (LEAKAGE

module top;
  logic q = 0;
  initial begin
    repeat (3) #5 q = ~q;
    #5 $display("PASS");
    $finish;
  end
endmodule
