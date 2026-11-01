// CLAUSE: standard pragma
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.11: pragmas the tool does not recognise have no effect on the source (x is 5 then 7).
// CHECK: x=7

`pragma made_up_pragma value=3, list=("a", 2)
module top;
  int x = 5;
  `pragma another_unknown
  initial begin x = x + 2; $display("x=%0d", x); end
endmodule
