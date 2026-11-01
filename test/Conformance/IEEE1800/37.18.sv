// CLAUSE: header declaration vpiPackedArrayVar
// XFAIL: *
// The dedicated Packed array variables object type runtime check does not reach its expected result.
// RUN: %clang -c -fPIC %S/Inputs/37.18/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[1:0][3:0] a;
import "DPI-C" context function int probe();
initial begin

if(!probe())$fatal(1,"object type");
$display("PASS");$finish;
end
endmodule
