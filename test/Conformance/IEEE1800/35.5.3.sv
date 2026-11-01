// CLAUSE: context scope userdata
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.3/export_same.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child_type;timeunit 1ns;timeprecision 1ns;
export "DPI-C" function sv_f;function int sv_f();return 1;endfunction endmodule
module top;timeunit 1ns;timeprecision 1ns;child_type child();
export "DPI-C" function sv_f;function int sv_f();return 2;endfunction
import "DPI-C" context function int c35_export_same();
initial begin if(c35_export_same()!=1)$fatal(1,"same identifier export");$display("PASS");$finish;end endmodule
