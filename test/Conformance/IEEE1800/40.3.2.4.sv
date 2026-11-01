// CLAUSE: save reset merge
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=toggle -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit q;int saved,merged;
initial begin
saved=$coverage_save(`SV_COV_TOGGLE,"current_run");
merged=$coverage_merge(`SV_COV_TOGGLE,"current_run");$display("SAVED=%0d MERGED=%0d",saved,merged);
if(saved!=`SV_COV_OK || merged!=`SV_COV_OK)$fatal(1,"current run merge");
$display("PASS"); $finish;
end
endmodule
