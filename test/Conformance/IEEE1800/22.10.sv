// CLAUSE: celldefine directive
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/22.10/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=read %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins 22.10: modules between `celldefine and `endcelldefine are cells (vpiCellInstance); others are not.
// CHECK: cell leaf=1 plain=0

`celldefine
module leaf; endmodule
`endcelldefine
module plain; endmodule
module top;
  import "DPI-C" function int is_cell(string path);
  leaf l();  plain p();
  initial $display("cell leaf=%0d plain=%0d", is_cell("top.l"), is_cell("top.p"));
endmodule
