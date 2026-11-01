// CLAUSE: Elaboration severity tasks stop or allow simulation; the same tasks in a procedure run at run time
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/20.10.1/fatal.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/20.10.1/error.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// DIAG: $fatal encountered: elaboration fatal
// DIAG: $error encountered: elaboration error
// DIAG: $info encountered: info N=3
// DIAG: $warning encountered: warning N=3
// CHECK-DAG: simulation started
// CHECK-DAG: run time error
// CHECK-DAG: after run time error
// CHECK-DAG: run time fatal
// CHECK-NOT: not reached

// 20.10.1: $fatal and $error at elaboration keep simulation from starting, $info and $warning do not, a generate
// branch that is not taken runs nothing, and inside initial the same names are run-time severity tasks.
module top #(parameter int N = 3);
  if (N < 1) $fatal(1, "not elaborated");
  if (N == 3) $info("info N=%0d", N);
  if (N == 3) $warning("warning N=%0d", N);
  initial begin
    $display("simulation started");
    $error("run time error");
    $display("after run time error");
    $fatal(1, "run time fatal");
    $display("not reached");
  end
endmodule
