// CLAUSE: User-defined system task names are registered, with case, digits, underscores and $ significant
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.3.1/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: called $my_task
// CHECK: called $MY_TASK
// CHECK: called $a1_b$c
// 36.3: "the name is case sensitive" and its characters are letters, digits, _ and $.

module top;
  initial begin
    $my_task;
    $MY_TASK;
    $a1_b$c;
    $finish;
  end
endmodule
