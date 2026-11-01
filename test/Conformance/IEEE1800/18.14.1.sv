// CLAUSE: Parent seeding reproduces an existing child stream
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  process parent;
  int a, b, extra;
  initial begin
    parent = process::self();
    parent.srandom(17);
    fork a = $urandom; join
    parent.srandom(17);
    fork
      b = $urandom;
      extra = $urandom;
    join
    if (a != b) $fatal(1, "hierarchical replay");
    $display("PASS");
  end
endmodule
