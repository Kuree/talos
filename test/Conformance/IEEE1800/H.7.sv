// CLAUSE: dpi dynamic open array
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.7/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  import "DPI-C" function int dpi_sum(input int values[]);
  int a[];

initial begin

  a='{1,2,3}; if(dpi_sum(a)!=6) $fatal(1,"DPI open dynamic");

$display("PASS");
$finish;
end
endmodule
