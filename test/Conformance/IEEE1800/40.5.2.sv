// CLAUSE: vpi_get coverage properties on instance, signal and assertion handles, and FSM iteration
// XFAIL: *
// vpi_get returns vpiUndefined for coverage properties, and vpi_iterate(vpiFsm) returns null; only vpi_control is implemented.
// RUN: %clang -c -fPIC %S/Inputs/40.5.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full --coverage %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: signal covered=2 max=4
// CHECK: instance toggle=1
// CHECK: aundf covered=0 attempt=1 success=0 failure=0
// CHECK: afail covered=0 attempt=1 success=0 failure=1
// CHECK: apass covered=1 attempt=1 success=1 failure=0
// CHECK: max=1
// CHECK: fsm covered=2 max=3 states=3
// CHECK: fsm expression=top.cs

// 40.5.2: for a signal the entities are its bits. Table 40-3 gives the assertion results used here. The FSM has two of
// three states reached.
module top;
  logic [3:0] s = 0;
  bit on = 1, off = 0, clk;
  /* tool state_vector cs enum F */
  logic [1:0] cs = 0;
  parameter /* tool enum F */ S0 = 0, S1 = 1, S2 = 2;
  aundf: assert property (@(posedge clk) on ##[1:$] off);
  afail: assert property (@(posedge clk) on ##1 off) else ;
  apass: assert property (@(posedge clk) on ##1 on);
  import "DPI-C" context function void probe();
  initial begin
    #1 s = 4'b0011; #1 s = 0; cs = S1;
    repeat (8) #1 clk = ~clk;
    #1 probe();
    $finish;
  end
endmodule
