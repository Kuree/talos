// CLAUSE: header declaration vpiLetDecl
// XFAIL: *
// The dedicated Let object type runtime check does not reach its expected result.
// RUN: %clang -c -fPIC %S/Inputs/37.57/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
let f(x)=x+1;
import "DPI-C" context function int probe();
initial begin

if(!probe())$fatal(1,"object type");
$display("PASS");$finish;
end
endmodule
