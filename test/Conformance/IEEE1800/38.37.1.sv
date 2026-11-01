// CLAUSE: System task and function callbacks: compiletf at build, sizetf sets a sized function's width (32 without one), calltf reads arguments and returns the value
// XFAIL: *
// User-defined system tasks and functions called from source are rejected at compile time (37.3.5).
// RUN: %clang -shared -fPIC %S/Inputs/38.37.1/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: calltf user=func compiled=1 sum=7
// CHECK-NEXT: sum=7 bits=8 unsized bits=32
// CHECK-NEXT: task args=1

module top;
int a = 3;
int sum;
initial begin
  sum = $sum8(a, 4);
  $display("sum=%0d bits=%0d unsized bits=%0d", sum, $bits($sum8(a, 4)), $bits($unsized()));
  $count_args(a);
  $finish;
end
endmodule
