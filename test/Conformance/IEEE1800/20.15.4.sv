// CLAUSE: Queue fullness changes at the configured capacity
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int status;
  initial begin
    $q_initialize(1, 1, 1, status);
    if ($q_full(1, status) !== 0 || status != 0) $fatal(1, "empty queue");
    $q_add(1, 7, 0, status);
    if ($q_full(1, status) !== 1 || status != 0) $fatal(1, "full queue");
    $display("PASS");
  end
endmodule
