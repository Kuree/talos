// CLAUSE: Startup routines may register the six early callback reasons, and access begins at cbEndOfCompile
// XFAIL: *
// cbUnresolvedSystf, cbError and cbPLIError are not implemented, and a startup table registering one crashes in talos_rt_v1_vpi_end_compile.
// RUN: %clang -shared -fPIC %S/Inputs/36.10.2/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: startup lookup=0
// CHECK: cbEndOfCompile=1
// CHECK: cbStartOfSimulation=1
// CHECK: cbEndOfSimulation=1
// CHECK: cbUnresolvedSystf=1
// CHECK: cbError=1
// CHECK: cbPLIError=1
// CHECK: end of compile lookup=1
// 36.10.2 lists the six reasons a startup routine can register, and from cbEndOfCompile "all functionality is available".

module top;
  int n = 7;
  initial $finish;
endmodule
