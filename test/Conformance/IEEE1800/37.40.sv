// CLAUSE: Timing check: a tchk gives its type, reference and data terms with edges and conditions, its limit, notifier, and vpiExpr argument list
// XFAIL: *
// timing check objects are not iterated (no timing checks reported)
// RUN: %clang -c -fPIC %S/Inputs/37.40/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: tchk type=vpiTchk setup=1 hold=0 ref=clk ref_edge=pos data=d data_edge=none data_cond=null limit=3 notifier=ntf
// CHECK-DAG: tchk type=vpiTchk setup=0 hold=1 ref=clk ref_edge=pos data=d data_edge=none data_cond=en limit=4 notifier=null
// CHECK: arg vpiTchkTerm
// CHECK-NEXT: arg vpiTchkTerm
// CHECK-NEXT: arg vpiConstant
// CHECK-NEXT: arg vpiLogicVar

// Detail 1: for $setup and $hold alike the reference term is posedge clk and the data term is d. Detail 2: the argument types.
`timescale 1ns/1ns
module dut(input d, input clk, input en);
  logic ntf;
  specify
    $setup(d, posedge clk, 3, ntf);
    $hold(posedge clk, d &&& en, 4);
  endspecify
endmodule
module top;
  logic d = 0, clk = 0, en = 1;
  dut u(d, clk, en);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
