// CLAUSE: Canonical access to packed elements of queues
// XFAIL: *
// Slang 11 rejects the queue actual before C can access its packed elements.
// RUN: %clang -c -fPIC %S/Inputs/H.12.3/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function void edit(inout logic [35:0] a[]);
  logic [35:0] q[$];
  initial begin
    q = '{36'hx_00000001, 36'hz_00000002};
    edit(q);
    if (q[0] !== 36'hz_00000002 || q[1] !== 36'hx_00000001)
      $fatal(1, "canonical vector access");
    $display("PASS");
  end
endmodule
