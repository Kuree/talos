// CLAUSE: VPI calls
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38/vpi_basic.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  import "DPI-C" context function int probe_vpi_array();
  integer a[7:5]='{10,20,30};

initial begin

  if(probe_vpi_array()!=60) $fatal(1,"VPI array indices");

$display("PASS");
$finish;
end
endmodule
