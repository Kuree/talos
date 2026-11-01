// CLAUSE: Thread RNG values ignore thread execution order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  process parent;
  int a, b, noise;
  initial begin
    parent = process::self();
    parent.srandom(17);
    fork
      #1 a = $urandom;
      noise = $urandom;
    join
    parent.srandom(17);
    fork
      b = $urandom;
      #1 noise = $urandom;
    join
    if (a != b) $fatal(1, "thread stability");
    $display("PASS");
  end
endmodule
