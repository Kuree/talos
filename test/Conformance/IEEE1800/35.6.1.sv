// CLAUSE: Copy-in and copy-out of queue actuals
// XFAIL: *
// Slang 11 rejects a queue actual for an inout DPI open-array formal.
// RUN: %clang -c -fPIC %S/Inputs/35.6.1/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function void edit(inout int a[]);
  int q[$];
  initial begin
    q = '{4, 7, 9};
    edit(q);
    if (q.size() != 3 || q[0] != 9 || q[1] != 7 || q[2] != 4)
      $fatal(1, "queue copy-out");
    $display("PASS");
  end
endmodule
