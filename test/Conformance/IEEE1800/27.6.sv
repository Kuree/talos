// CLAUSE: implicit genblk collision numbering
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: {{SCOPE=top\.genblk02}}

module top;
timeunit 1ns; timeprecision 1ns;
localparam int genblk2=0; if(1) begin:g localparam int x=1; end if(1) begin initial $display("SCOPE=%m"); end
initial begin
#1;
$display("PASS"); $finish;
end
endmodule
