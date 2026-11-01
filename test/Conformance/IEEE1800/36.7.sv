// CLAUSE: vpi_user.h and sv_vpi_user.h supply the codes an application compares with live objects
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/36.7/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: u is vpiModule=1
// CHECK: b is vpiInterface=1
// 36.7: vpiModule comes from vpi_user.h (Annex K) and vpiInterface from sv_vpi_user.h (Annex M).

interface bus;
endinterface
module leaf;
endmodule
module top;
  leaf u();
  bus b();
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
