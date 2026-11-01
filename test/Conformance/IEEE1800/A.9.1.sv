// CLAUSE: Attribute instance attached to a declaration
// XFAIL: *
// vpi_iterate(vpiAttribute) yields no attributes, so the attribute is not observable through VPI.
// RUN: %clang -c -fPIC %S/Inputs/A.9.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=read %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins A.9.1/5.12: the attribute instance attached to a declaration is readable through vpiAttribute with its name and value.
// CHECK: keep=1 missing=-1

module top;
  import "DPI-C" function int attr(string path, string name);
  (* keep = 1 *) bit n = 1;
  initial $display("keep=%0d missing=%0d", attr("top.n", "keep"), attr("top.n", "nothere"));
endmodule
