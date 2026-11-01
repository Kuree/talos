// CLAUSE: instance use binding
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier --libmap %S/Inputs/33.7/map.lib %s -o %t.exe
// RUN: %t.exe
// Pins 33.7: %l prints the library.cell binding of the module containing the call: work.top for the root, lb.leaf for the child bound from lb.
// CHECK-DAG: TOP=work.top
// CHECK-DAG: LEAF=lb.leaf

module top;
  leaf l();
  initial $display("TOP=%l", 0);
endmodule
config cfg; design work.top; default liblist lb work; endconfig
