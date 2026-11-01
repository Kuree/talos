// CLAUSE: Configuration binding illustrations
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier --libmap %S/Inputs/33.6/map.lib %s -o %t.exe
// RUN: %t.exe
// Pins 33.6: the cell clause binds adder to the gate library implementation (a+b+8) even though rtl comes first in the default liblist.
// CHECK: SUM=11

module top;
  wire [7:0] sum;
  adder u(.a(8'd1), .b(8'd2), .sum(sum));
  initial begin #1; $display("SUM=%0d", sum); end
endmodule
config cfg; design work.top; default liblist rtl gate; cell adder use gate.adder; endconfig
