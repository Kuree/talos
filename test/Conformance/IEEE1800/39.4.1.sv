// CLAUSE: cbAssertionSys* callbacks fire with their reason and user_data when the assertion system is controlled
// XFAIL: *
// vpi_register_cb rejects every cbAssertionSys* reason with "reason is not implemented", and vpi_control rejects every vpiAssertionSys* operation.
// RUN: %clang -c -fPIC %S/Inputs/39.4.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: registered=7
// CHECK-NEXT: fired off reason=1
// CHECK-NEXT: fired on reason=1
// CHECK-NEXT: fired lock reason=1
// CHECK-NEXT: fired unlock reason=1
// CHECK-NEXT: fired kill reason=1
// CHECK-NEXT: fired reset reason=1
// CHECK-NEXT: fired end reason=1

module top;
logic clk = 0, x = 1;
a: assert property (@(posedge clk) x);
import "DPI-C" context function void probe();
initial begin
  #1 clk = 1;
  #1 probe();
  $finish;
end
endmodule
