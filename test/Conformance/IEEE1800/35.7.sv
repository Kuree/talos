// CLAUSE: context export function scope
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.7/export_function.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child_type;export "DPI-C" function sv_export_calc;function int sv_export_calc(input int a);return a+10;endfunction endmodule
module top;child_type child();
export "DPI-C" function sv_export_calc;function int sv_export_calc(input int a);return a+100;endfunction
import "DPI-C" context function int c35_export_call();
initial begin if(c35_export_call()!=13103)$fatal(1,"export scope");$display("PASS");$finish;end endmodule
