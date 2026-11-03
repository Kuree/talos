// IEEE 1800-2023 38.36.3: $error and $fatal are simulation run-time errors
// (20.10) and deliver cbError callbacks, in which vpi_chk_error reports them.
// $error does not end the simulation; $fatal does, after its callbacks. A
// callback removed during delivery runs no more.
// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi_run_time_error.c -I%resource_dir/include -o %t.so
// RUN: talos -O3 --vpi=full %s %t.so -o %t
// RUN: not %t > %t.out 2>&1
// RUN: FileCheck %s --input-file=%t.out
// RUN: FileCheck %s --check-prefix=RUNNING --input-file=%t.out

module top;
  initial begin
    $error("first problem");
    $warning("just a warning");
    #1 $display("still running");
    $error("second problem");
    $fatal(1, "last problem");
  end
endmodule

// The callbacks run when the error is raised, just before its report;
// $warning is not an error.
// CHECK: cbError registered=1
// CHECK-NEXT: cbError registered=1
// CHECK-NEXT: cbError user=error level=3 message=run-time error
// CHECK-NEXT: after a call level=0
// CHECK-NEXT: cbError user=second level=3
// CHECK-NEXT: removed=1
// CHECK-NEXT: ERROR: {{.*}}first problem
// CHECK-NEXT: WARNING: {{.*}}just a warning
// CHECK-NOT: user=second
// CHECK: cbError user=error level=3 message=run-time error
// CHECK-NEXT: after a call level=0
// CHECK-NEXT: ERROR: {{.*}}second problem
// CHECK: cbError user=error level=3 message=run-time fatal error
// CHECK-NEXT: after a call level=0
// CHECK-NEXT: FATAL: {{.*}}last problem
// RUNNING: still running
