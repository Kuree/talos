// CLAUSE: Table 36-10 current behaviour: vpiVariables has vpiReg and vpiRegArray, and an integer array is a vpiRegArray
// XFAIL: *
// vpi_iterate(vpiReg, array) returns null, so the elements that detail 6 of Table 36-10 describes cannot be iterated.
// RUN: %clang -c -fPIC %S/Inputs/36.12.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: r in vpiVariables=1
// CHECK: m in vpiVariables=1
// CHECK: ia is vpiRegArray=1
// CHECK: ia element is vpiIntegerVar=1
// 36.12.1 details 3, 5 and 6: the IEEE Std 1800 column of Table 36-10, with no compatibility mode selected.

module top;
  reg r;
  reg m[2];
  integer ia[2];
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
