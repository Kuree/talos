// CLAUSE: A uwire follows its single driver; a second driver or a pass switch connection is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.6.2/tran.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.6.2/two_drivers.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: 'uwire' net 'n' cannot be connected to 'inout' port
// DIAG: 'uwire' net 'n' cannot have multiple drivers
// CHECK: 0 0101 z{{$}}
// CHECK-NEXT: 1 1010 z{{$}}
// CHECK-NEXT: x xxxx z{{$}}

// 6.6.2: the illegal side is the rule; the legal side reads a uwire through 0, 1 and x, and undriven as z.
module top;
  logic d = 0;
  uwire n;
  uwire undriven;
  uwire [3:0] v;
  assign n = d;
  assign v = {d, ~d, d, ~d};
  initial begin
    #1 $display("%b %b %b", n, v, undriven);
    d = 1;
    #1 $display("%b %b %b", n, v, undriven);
    d = 1'bx;
    #1 $display("%b %b %b", n, v, undriven);
    $finish;
  end
endmodule
