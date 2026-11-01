// CLAUSE: standard pragma
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.11.1: reset/resetall restore pragma defaults and do not disturb simulated values (x=15). Their visible effect is only on protect envelopes (clause 34, not implemented here).
// CHECK: x=15

`pragma reset made_up_pragma
module top;
  int x = 5;
  initial begin
    x = x * 3;
    `pragma resetall
    $display("x=%0d", x);
  end
endmodule
