// CLAUSE: Imported functions and tasks exchange results and output arguments with C; ref arguments are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/35.5/illegal.sv -o %t.bad.exe
// RUN: %clang -c -fPIC %S/Inputs/35.5/dpi.c -I%resource_dir/include -o %t.dpi.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.dpi.o -o %t.exe
// RUN: %t.exe
// DIAG: DPI subroutines cannot have 'ref' arguments
// CHECK: function 7{{$}}
// CHECK-NEXT: linkage name 42{{$}}
// CHECK-NEXT: output 6 inout 10{{$}}
// CHECK-NEXT: pure 2.50{{$}}
// CHECK-NEXT: task 9 input 3{{$}}

// 35.5: each value is computed in C, so the probe fails unless the call reaches the C function and returns.
module top;
  import "DPI-C" function int add(input int a, input int b);
  import "DPI-C" c_twice = function int sv_twice(input int a);
  import "DPI-C" function void fill(output int o, inout int io);
  import "DPI-C" pure function real half(input real x);
  import "DPI-C" task square(input int a, output int o);
  int o = 0, io = 5, s = 0, a = 3;
  initial begin
    $display("function %0d", add(a, 4));
    $display("linkage name %0d", sv_twice(21));
    fill(o, io);
    $display("output %0d inout %0d", o, io);
    $display("pure %0.2f", half(5.0));
    square(a, s);
    $display("task %0d input %0d", s, a);
    $finish;
  end
endmodule
