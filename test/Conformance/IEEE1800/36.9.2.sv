// CLAUSE: Callbacks fire for a value change, a time and a simulator action
// XFAIL: *
// vpi_register_cb reports cbValueChange as not implemented (docs/vpi.md); cbAfterDelay and cbEndOfSimulation fire.
// RUN: %clang -shared -fPIC %S/Inputs/36.9.2/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: value change t=1 v=1
// CHECK: after delay t=2 v=1
// CHECK: value change t=3 v=0
// CHECK: end of simulation t=4
// 36.9.2: "Simulation event", "Simulation time" and "Simulator action or feature" callbacks. Systf callbacks are in 36.9.1.

module top;
  bit v;
  initial begin
    #1 v = 1;
    #2 v = 0;
    #1 $finish;
  end
endmodule
