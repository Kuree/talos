// CLAUSE: VPI coverage enumerations: control codes and coverage properties act on toggle coverage
// XFAIL: *
// vpi_get returns vpiUndefined for the coverage properties of 40.5.1; only vpi_control is implemented.
// RUN: %clang -c -fPIC %S/Inputs/40.5.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full --coverage=toggle %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: get equal=1 nonzero=1
// CHECK: check=1
// CHECK: reset=1
// CHECK: after reset=0

// 40.5.1 enumerates the codes used here. The covered count through VPI must equal $coverage_get.
module top;
  bit q;
  import "DPI-C" context function int covered();
  import "DPI-C" context function int control(input int code);
  initial begin
    #1 q = 1; #1 q = 0; #1;
    $display("get equal=%0d nonzero=%0d", covered() == $coverage_get(`SV_COV_TOGGLE, `SV_COV_MODULE, top), covered() > 0);
    $display("check=%0d", control(3));
    $display("reset=%0d", control(2));
    $display("after reset=%0d", covered());
    $finish;
  end
endmodule
