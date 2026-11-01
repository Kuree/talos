// CLAUSE: integer literal expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.3.3: the clause example; unsized based literals are unsigned, sd literals signed, sized signed 4'sd12 is -4.
// CHECK: v=-4 1431655761 -4 1

module top;
  int a, b, c, d;
  initial begin
    a = -12/3; b = -'d12/3; c = -'sd12/3; d = -4'sd12/3;
    $display("v=%0d %0d %0d %0d", a, b, c, d);
  end
endmodule
