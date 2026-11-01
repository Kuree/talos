// CLAUSE: instance use binding
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf #(parameter int VALUE=7); endmodule
module alternative #(parameter int VALUE=11); endmodule
module top; leaf a(); leaf b(); initial begin
if(a.VALUE!=19 || b.VALUE!=19)$fatal(1,"binding a=%0d b=%0d",a.VALUE,b.VALUE);
$display("BINDING=%l");$display("PASS");$finish;end endmodule
config selected_config; design work.top; default liblist work; cell leaf use #(.VALUE(19)); endconfig
