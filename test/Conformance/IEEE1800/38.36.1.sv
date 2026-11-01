// CLAUSE: Value-change callback delivery
// XFAIL: *
// Value-change callbacks are unavailable.
// RUN: %clang -c -fPIC %S/Inputs/38.36.1/vpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value=0;
import "DPI-C" context function int register_change();
import "DPI-C" context function int change_count();
initial begin
#1;if(!register_change())$fatal(1,"registration");
value=1;
#1;if(change_count()!=1)$fatal(1,"callback count");
$display("PASS");$finish;
end
endmodule
