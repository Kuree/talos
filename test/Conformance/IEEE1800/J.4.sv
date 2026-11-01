// CLAUSE: A DPI shared library can be included in the program
// SINCE: 0.1.0
// REQUIRES: native-elf
// RUN: %clang -shared -fPIC %S/Inputs/J.4/foreign.c -o %t.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier -sv_lib %t %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;import "DPI-C" function int foreign_value();initial begin if(foreign_value()!=7)$fatal(1,"DPI shared library");$display("PASS");$finish;end endmodule
