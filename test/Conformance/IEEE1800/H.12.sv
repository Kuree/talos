// CLAUSE: Passing queue and fixed array ranges to the same import
// XFAIL: *
// Slang 11 rejects the queue actual for this DPI open-array import.
// RUN: %clang -c -fPIC %S/Inputs/H.12/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function int dpi_sum(input int values[]);
  int q[$];
  int fixed_values[3:1] = '{6, 2, 1};

  initial begin
    q = '{1, 2, 3};
    if (dpi_sum(q) != 6) $fatal(1, "queue sum");
    if (dpi_sum(fixed_values) != 9) $fatal(1, "fixed array sum");
    $display("PASS");
  end
endmodule
