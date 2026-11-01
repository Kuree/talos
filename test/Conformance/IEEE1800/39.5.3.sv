// CLAUSE: On a pending deferred assertion, vpiAssertionReset flushes its report and vpiAssertionDisable leaves it to mature
// XFAIL: *
// Deferred assertions have no VPI handle (not found by name nor by vpi_iterate(vpiAssertion, instance)), and vpi_control returns 0 "not supported" for vpiAssertionReset and vpiAssertionDisable.
// RUN: %clang -c -fPIC %S/Inputs/39.5.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: flushed found=1 reset=1
// CHECK-NEXT: matured found=1 disable=1
// CHECK-NEXT: matured report
// CHECK-NOT: flushed report

module top;
logic ok = 0;
import "DPI-C" context function void reset_flushed();
import "DPI-C" context function void disable_matured();
initial begin
  // Both fail now, and their reports wait in the deferred assertion report queue.
  flushed: assert #0 (ok) else $display("flushed report");
  reset_flushed();
  matured: assert #0 (ok) else $display("matured report");
  disable_matured();
  #1 $finish;
end
endmodule
