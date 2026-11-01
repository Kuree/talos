// CLAUSE: sizetf, compiletf and calltf each receive the registered user_data
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.8.4/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: sizetf user_data=165
// CHECK: compiletf user_data=165
// CHECK: calltf user_data=165

module top;
  initial begin
    $display("bits=%0d", $bits($tagged()));
    void'($tagged());
    $finish;
  end
endmodule
