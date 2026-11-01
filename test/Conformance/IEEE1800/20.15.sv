// CLAUSE: A stochastic LIFO queue returns its newest entry
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int status, job, info;
  initial begin
    $q_initialize(1, 2, 2, status);
    $q_add(1, 10, 100, status);
    $q_add(1, 20, 200, status);
    $q_remove(1, job, info, status);
    if (status != 0 || job != 20) $fatal(1, "LIFO order");
    $display("PASS");
  end
endmodule
