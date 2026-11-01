// CLAUSE: VPI C header
// XFAIL: *
// The supplied 2023 compatibility selection expands to an empty preprocessor expression.
// RUN: %clang -c -fPIC %S/Inputs/K/compat.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import "DPI-C" context function int compat_probe();integer value=7;initial begin if(compat_probe()!=7)$fatal(1,"compatibility value");$display("PASS");$finish;end endmodule
