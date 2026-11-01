// CLAUSE: Adding a queue entry preserves its job and information
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int status, job, info;
  initial begin
    $q_initialize(1, 1, 1, status);
    $q_add(1, 7, 19, status);
    if (status != 0) $fatal(1, "queue add");
    $q_remove(1, job, info, status);
    if (status != 0 || job != 7 || info != 19) $fatal(1, "entry data");
    $display("PASS");
  end
endmodule
