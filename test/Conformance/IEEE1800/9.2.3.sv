// CLAUSE: Final procedures run once at the end of simulation; a delay in a final procedure is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.3/implicit.sv -o %t.implicit.exe
// RUN: %t.implicit.exe
// DIAG: statements that pass time are not allowed in this context
// CHECK: final n=2 t=5{{$}}
// CHECK-NEXT: final n=7 t=4{{$}}

// 9.2.3: one print each for $finish and for running out of events; n=3 at 10 never happens after the $finish at 5.
module top;
  timeunit 1ns; timeprecision 1ns;
  int n = 0;
  final $display("final n=%0d t=%0t", n, $time);
  initial begin
    n = 1;
    #5 n = 2;
    $finish;
  end
  initial #10 n = 3;
endmodule
