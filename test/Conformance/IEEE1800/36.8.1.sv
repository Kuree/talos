// CLAUSE: sizetf sets a system function's width, runs at most once, and is skipped for real functions
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.8.1/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: sized value=165 bits=8
// CHECK: default bits=32
// CHECK: real value=1.5
// CHECK: sizetf sized=1 real=0
// 36.8.1: "called at most once"; "If no sizetf routine is specified, ... 32 bits"; "shall not be called ... vpiRealFunc".

module top;
  initial begin
    $display("sized value=%0d bits=%0d", $sized(), $bits($sized()));
    $display("default bits=%0d", $bits($plain()));
    $display("real value=%0.1f", $realf());
    $finish;
  end
endmodule
