// CLAUSE: Process: vpiProcess lists initial, final and always; vpiAlwaysType tells the always kinds apart; vpiStmt and vpiModule relate them
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.63/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: vpiInitial always=none stmt=vpiBegin module=top
// CHECK-DAG: vpiFinal always=none stmt=vpiSysTaskCall module=top
// CHECK-DAG: vpiAlways always=vpiAlways stmt=vpiEventControl module=top
// CHECK-DAG: vpiAlways always=vpiAlwaysComb stmt=vpiAssignment module=top
// CHECK-DAG: vpiAlways always=vpiAlwaysFF stmt=vpiEventControl module=top
// CHECK-DAG: vpiAlways always=vpiAlwaysLatch stmt=vpiIf module=top
// CHECK: processes=6
// CHECK: bye

module top;
logic c, d, a, b, f, l;
import "DPI-C" context function void probe();
always @(posedge c) a = d;
always_comb b = d;
always_ff @(posedge c) f <= d;
always_latch if (c) l <= d;
final $display("bye");
initial begin
  #1 probe();
  $finish;
end
endmodule
