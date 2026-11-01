// CLAUSE: keyword 1800 2012
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.14.8/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.14.8: soft is an identifier under 1800-2009 and the soft-constraint keyword under 1800-2012 (illegal.sv uses it as an identifier).
// DIAG: expected a declaration name
// CHECK-DAG: L soft=4
// CHECK-DAG: S x=5

`begin_keywords "1800-2009"
module legacy;
  int soft = 4;                 // `soft` is not a keyword before 1800-2012 (Table 22-6)
  initial $display("L soft=%0d", soft);
endmodule
`end_keywords
`begin_keywords "1800-2012"
module top;
  class C; rand int x; constraint c {x inside {[1:9]}; soft x == 5;} endclass
  legacy l();
  initial begin C o = new; void'(o.randomize()); $display("S x=%0d", o.x); end
endmodule
`end_keywords
