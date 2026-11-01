// CLAUSE: A linked C application runs inside the simulation and observes it as it executes
// SINCE: 0.1.0
// RUN: %clang -shared -fPIC %S/Inputs/36.6/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: t=2 n=8
// CHECK: end n=9
// 36.6: applications are "C functions that are linked into a tool", interacting "as the SystemVerilog source code is executed".

module top;
  int n = 7;
  initial begin
    #1 n = 8;
    #2 n = 9;
    $finish;
  end
endmodule
