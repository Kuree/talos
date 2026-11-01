// CLAUSE: A compile-time symbol binds one application to a compatibility mode, and two symbols are an error
// XFAIL: *
// vpi_compatibility.h, as printed in Annex L, has an empty #if for 2017 mode and a wrapped one-symbol guard, and the runtime has no vpi_*_<mode> routines.
// RUN: %not %clang -c -fPIC %S/Inputs/36.12.2.1/two.c -I%resource_dir/include -o %t.two.o
// RUN: %clang -c -fPIC %S/Inputs/36.12.2.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %clang -c -fPIC %S/Inputs/36.12.2.1/legacy.c -I%resource_dir/include -o %t.helper1.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o %t.helper1.o -o %t.exe
// RUN: %t.exe
// DIAG: Only one VPI_COMPATIBILITY_VERSION symbol definition is allowed
// CHECK: current regs=1 others=1
// CHECK: 1364v2001 regs=0 others=1
// 36.12.1 detail 5: in IEEE Std 1364, vpiVariables excludes vpiReg. One application uses that mode, and the other does not.

module top;
  reg r;
  integer i;
  import "DPI-C" context function void current();
  import "DPI-C" context function void legacy();
  initial begin
    current();
    legacy();
    $finish;
  end
endmodule
