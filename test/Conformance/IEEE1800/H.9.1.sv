// CLAUSE: A hierarchical DPI call preserves its declaration scope
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.9.1/scope.c -I%resource_dir/include -o %t.scope.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.scope.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module leaf;import "DPI-C" context function int scope_ok();endmodule
module top;leaf d();initial begin if(!d.scope_ok())$fatal(1,"DPI declaration scope");$display("PASS");$finish;end endmodule
