// CLAUSE: context export timed task
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.8/export_task.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
export "DPI-C" task sv_export_wait;task sv_export_wait(output int out);#3;out=17;endtask
import "DPI-C" context task c35_export_task(output int out);int out;
initial begin
c35_export_task(out);if($time!=3 || out!=17)$fatal(1,"export task time=%0t out=%0d",$time,out);
$display("PASS"); $finish;
end
endmodule
