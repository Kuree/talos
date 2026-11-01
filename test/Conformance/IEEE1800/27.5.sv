// CLAUSE: direct nested same name
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
localparam int P=2; if(P==0) begin:s int v=3; end else if(P==1) begin:s int v=5; end else begin:s int v=7; end
initial begin
if(s.v!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
