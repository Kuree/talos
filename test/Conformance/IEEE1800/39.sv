// CLAUSE: Assertion API
// XFAIL: *
// vpi_register_assertion_cb is declared but has no linkable implementation.
// RUN: %clang -c -fPIC %S/Inputs/39/vpi_assertion.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  import "DPI-C" context function int probe_assertion_api();
  bit clk=0;
  always #5 clk=~clk;
  p: assert property (@(posedge clk) 1'b1);
  initial begin #1; if(probe_assertion_api()!=1) $fatal(1,"assertion API registration"); #10; $display("PASS"); $finish; end
endmodule
