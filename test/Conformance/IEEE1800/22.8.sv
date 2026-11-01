// CLAUSE: reset preserves macro
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.8/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.8: the implicit net takes the type of the last `default_nettype (tri1 pulls z to 1, wand resolves to 0) and `resetall restores wire; none makes it an error (illegal.sv).
// DIAG: undeclared identifier
// CHECK-DAG: TRI1 p=1
// CHECK-DAG: WAND q=0
// CHECK-DAG: WIRE r=z

`default_nettype tri1
module m1;  assign p = 1'bz;  initial begin #1; $display("TRI1 p=%b", p); end endmodule
`default_nettype wand
module m2;  assign q = 1'b1;  assign q = 1'b0;  initial begin #1; $display("WAND q=%b", q); end endmodule
`resetall
module top;
  m1 a();  m2 b();
  assign r = 1'bz;
  initial begin #1; $display("WIRE r=%b", r); end
endmodule
