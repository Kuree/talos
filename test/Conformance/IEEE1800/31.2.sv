// CLAUSE: Timing checks in specify blocks honor event conditions; procedural timing checks are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/31.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: unknown system name '$setup'
// CHECK: 12 n=0{{$}}
// CHECK-NEXT: 24 n=1{{$}}
// CHECK-NEXT: 40 n=1{{$}}
// CHECK-NEXT: 52 n=0{{$}}

// 31.2: the notifier follows the event condition and the limit, so a check that never ran or ignored &&& fails here.
module ff(input d, input c, input en);
  timeunit 1ns; timeprecision 1ns;
  reg n = 0;
  specify
    $setup(d &&& en, posedge c, 2, n);
  endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  logic d = 0, c = 0, en = 0;
  ff u(d, c, en);
  task pulse(bit v, int gap);
    #10 d = v;
    #(gap) c = 1;
    #1 c = 0;
    $display("%0t n=%b", $time, u.n);
  endtask
  initial begin
    pulse(1, 1);             // condition false: no check
    en = 1;
    pulse(0, 1);             // violation toggles n
    pulse(1, 5);             // meets the limit
    pulse(0, 1);             // violation toggles n back
    $finish;
  end
endmodule
