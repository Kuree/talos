// CLAUSE: library map relative include
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config --libmap %S/Inputs/33.4.1.5/maps/root.map -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf #(parameter int VALUE=7); endmodule
module top; leaf a(); leaf b(); initial begin
if(a.VALUE!=7 || b.VALUE!=29)$fatal(1,"library binding a=%0d b=%0d",a.VALUE,b.VALUE);
$display("PASS");$finish;end endmodule
config selected_config;design work.top;default liblist work;instance top.b liblist gates;endconfig
