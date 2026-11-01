// CLAUSE: Reading a VPI expression performs its side effects
// XFAIL: *
// NOTE: User-defined VPI system tasks are rejected before their expression callbacks can run.
// RUN: %clang -c -fPIC %S/Inputs/37.3.5/expr.c -I%resource_dir/include -o %t.expr.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full %s %t.expr.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;int x=0;initial begin $touch(x++);if(x!=1)$fatal(1,"VPI expression evaluation");$display("PASS");$finish;end endmodule
