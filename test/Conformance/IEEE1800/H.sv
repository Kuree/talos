// CLAUSE: DPI C values
// XFAIL: *
// Queue actuals are rejected for imported DPI open arrays.
// RUN: %clang -c -fPIC %S/Inputs/H/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  import "DPI-C" function int dpi_sum(input int values[]);
  int q[$];

initial begin

  q='{1,2,3}; if(dpi_sum(q)!=6) $fatal(1,"DPI open queue");

$display("PASS");
$finish;
end
endmodule
