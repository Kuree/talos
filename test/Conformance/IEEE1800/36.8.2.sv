// CLAUSE: compiletf runs once per call site, before simulation starts
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.8.2/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: before simulation compiletf=2 calltf=0
// CHECK: after simulation compiletf=2 calltf=4
// 36.8.2: "called one time for each instance of a system task or system function in the source description". The loop has one.

module top;
  initial begin
    repeat (3) $checked;
    $checked;
    $finish;
  end
endmodule
