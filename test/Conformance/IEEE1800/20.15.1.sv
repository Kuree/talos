// CLAUSE: Queue identifiers must be unique
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int status;
  initial begin
    $q_initialize(1, 1, 1, status);
    if (status != 0) $fatal(1, "queue creation");
    $q_initialize(1, 1, 1, status);
    if (status != 6) $fatal(1, "duplicate queue");
    $display("PASS");
  end
endmodule
