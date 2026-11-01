// CLAUSE: vpi_control vpiAssertionSysOff and vpiAssertionSysOn stop and resume new assertion attempts, for one scope or for all
// XFAIL: *
// vpi_control returns 0 "not supported" for every vpiAssertionSys* operation, so the attempts continue.
// RUN: %clang -c -fPIC %S/Inputs/39.5.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: t=5 top pass
// CHECK-DAG: t=5 u pass
// CHECK: off u=1
// CHECK-NEXT: t=15 top pass
// CHECK-NEXT: on all=1
// CHECK-DAG: t=25 top pass
// CHECK-DAG: t=25 u pass
// CHECK: off all=1
// CHECK-NEXT: on all=1
// CHECK-DAG: t=45 top pass
// CHECK-DAG: t=45 u pass

`timescale 1ns/1ns
module sub(input logic clk, input logic ok);
a: assert property (@(posedge clk) ok) $display("t=%0t u pass", $time);
endmodule
module top;
logic clk = 0, ok = 1;
always #5 clk = ~clk;
sub u(clk, ok);
a: assert property (@(posedge clk) ok) $display("t=%0t top pass", $time);
import "DPI-C" context function void off_u();
import "DPI-C" context function void off_all();
import "DPI-C" context function void on_all();
initial begin
  #10 off_u();
  #10 on_all();
  #10 off_all();
  #10 on_all();
  #10 $finish;
end
endmodule
