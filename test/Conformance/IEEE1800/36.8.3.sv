// CLAUSE: calltf runs each time the system task executes, at the simulation time of the call
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.8.3/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: calltf time=2
// CHECK: calltf time=4
// CHECK: calltf time=6

module top;
  initial begin
    for (int i = 0; i < 3; i++) begin
      #2 $stamp;
    end
    $finish;
  end
endmodule
