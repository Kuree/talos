// CLAUSE: Querying empty and populated queue dimensions
// XFAIL: *
// Slang 11 rejects the queue actual before its bounds can be queried.
// RUN: %clang -c -fPIC %S/Inputs/H.12.2/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function int bounds(input int q[], input int n);
  int q[$];
  initial begin
    if (!bounds(q, 0)) $fatal(1, "empty queue bounds");
    q.push_back(3);
    if (!bounds(q, 1)) $fatal(1, "singleton queue bounds");
    q.push_front(5);
    if (!bounds(q, 2)) $fatal(1, "resized queue bounds");
    $display("PASS");
  end
endmodule
