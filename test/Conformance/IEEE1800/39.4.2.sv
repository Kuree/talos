// CLAUSE: assertion callback api
// XFAIL: *
// The runtime does not provide vpi_register_assertion_cb.
// RUN: %clang -c -fPIC %S/Inputs/39.4.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" context function int probe();
initial begin
if(!probe())$fatal(1,"symbol");
$display("PASS");$finish;
end
endmodule
