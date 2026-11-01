// CLAUSE: Frames: vpi_handle(vpiFrame, NULL) gives the active frame, whose parents, origins, current statements and automatic locals follow the call chain
// XFAIL: *
// vpiFrame objects are not iterated (no active frame reported)
// RUN: %clang -c -fPIC %S/Inputs/37.43/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: frame type=vpiFrame active={{[01]}} origin=inner stmt=vpiFuncCall thread=vpiThread
// CHECK-DAG: local x=21
// CHECK-DAG: local doubled=42
// CHECK: frame type=vpiFrame active={{[01]}} origin=outer stmt=vpiTaskCall thread=vpiThread
// CHECK-DAG: local y=7
// CHECK-DAG: local tag=8

// Details 4 and 5: inner's statement is the running probe() call; outer's statement is the call that activated inner.
module top;
  import "DPI-C" context function void probe();
  task automatic inner(input int x);
    int doubled = x * 2;
    probe();
  endtask
  task automatic outer(input int y);
    int tag = y + 1;
    inner(y * 3);
  endtask
  initial begin
    outer(7);
    $finish;
  end
endmodule
