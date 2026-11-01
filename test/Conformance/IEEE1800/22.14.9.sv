// CLAUSE: keyword 1800 2023
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.14.9/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.14.9: 1800-2023 reserves every earlier keyword (soft, implements) and adds none; illegal.sv uses implements as an identifier.
// DIAG: expected a declaration name
// CHECK: S x=6

`begin_keywords "1800-2023"
module top;
  class C; rand int x; constraint c {x inside {[1:9]}; soft x == 6;} endclass
  initial begin C o = new; void'(o.randomize()); $display("S x=%0d", o.x); end
endmodule
`end_keywords
