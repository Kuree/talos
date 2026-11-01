// CLAUSE: FIFO removal consumes entries in insertion order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int status, job, info;
  initial begin
    $q_initialize(1, 1, 2, status);
    $q_add(1, 10, 0, status);
    $q_add(1, 20, 0, status);
    $q_remove(1, job, info, status);
    if (status != 0 || job != 10) $fatal(1, "first removal");
    $q_remove(1, job, info, status);
    if (status != 0 || job != 20) $fatal(1, "second removal");
    $display("PASS");
  end
endmodule
