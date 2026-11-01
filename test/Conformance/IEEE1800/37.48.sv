// CLAUSE: Clocking block: vpiClockingBlock gives its name, event, default skews and edges, and its io decls with direction, skew, edge and referenced signal
// XFAIL: *
// clocking block event and skews are null (event=null, input_skew=none)
// RUN: %clang -c -fPIC %S/Inputs/37.48/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: block type=vpiClockingBlock name=cb
// CHECK: full=top.cb
// CHECK: event=posedge clk
// CHECK: default input_skew=2 output_skew=3 input_edge_none=1 output_edge_none=1
// CHECK: default_clocking=cb
// CHECK-DAG: io a input=1 output=0 expr=a input_skew=2 input_neg=0
// CHECK-DAG: io b input=0 output=1 expr=b output_skew=1 output_neg=0
// CHECK-DAG: io c input=1 output=0 expr=c input_skew=none input_neg=1

// Detail 1: the block's skews are the defaults; each io decl reports its own (a inherits the default, b and c override it).
`timescale 1ns/1ns
module top;
  logic clk = 0, a = 0, b = 0, c = 0;
  default clocking cb @(posedge clk);
    default input #2 output #3;
    input a;
    output #1 b;
    input negedge c;
  endclocking
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
