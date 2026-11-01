// CLAUSE: fork-join, join_any and join_none resume the parent as specified; return inside fork is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.3.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: return statement is not allowed in fork-join block
// CHECK: 10 a{{$}}
// CHECK-NEXT: 20 b{{$}}
// CHECK-NEXT: 20 after join{{$}}
// CHECK-NEXT: 25 c{{$}}
// CHECK-NEXT: 25 after join_any{{$}}
// CHECK-NEXT: 35 d{{$}}
// CHECK-NEXT: 35 after wait fork{{$}}
// CHECK-NEXT: 35 after join_none{{$}}
// CHECK-NEXT: 36 e{{$}}
// CHECK-NEXT: 38 k=1{{$}}
// CHECK-NEXT: 39 k=2{{$}}
// CHECK-NEXT: 40 k=3{{$}}

// 9.3.2: Table 9-1 in simulated times, delays count from entry to the block, and each spawn keeps its own k.
module top;
  timeunit 1ns; timeprecision 1ns;
  initial begin
    fork
      #20 $display("%0t b", $time);
      #10 $display("%0t a", $time);
    join
    $display("%0t after join", $time);
    fork
      #5 $display("%0t c", $time);
      #15 $display("%0t d", $time);
    join_any
    $display("%0t after join_any", $time);
    wait fork;
    $display("%0t after wait fork", $time);
    fork
      #1 $display("%0t e", $time);
    join_none
    $display("%0t after join_none", $time);
    #2;
    for (int j = 1; j <= 3; ++j)
      fork
        automatic int k = j;
        #k $display("%0t k=%0d", $time, k);
      join_none
    wait fork;
    $finish;
  end
endmodule
