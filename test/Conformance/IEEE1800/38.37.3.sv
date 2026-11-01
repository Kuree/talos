// CLAUSE: A static array registers several system tasks and functions in a loop; each call reaches its own calltf and returns its own value
// XFAIL: *
// User-defined system tasks and functions called from source are rejected at compile time (37.3.5).
// RUN: %clang -shared -fPIC %S/Inputs/38.37.3/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: my_task 1
// CHECK-NEXT: my_task 2
// CHECK-NEXT: int=41 sized=170 bits=8
// CHECK-NEXT: int calls=1 sized calls=1

module top;
import "DPI-C" context function void report();
int i, s;
initial begin
  $my_task;
  $my_task;
  i = $my_int_func();
  s = $my_sized_func();
  $display("int=%0d sized=%0d bits=%0d", i, s, $bits($my_sized_func()));
  report();
  $finish;
end
endmodule
