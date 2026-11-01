// CLAUSE: Directives
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define VALUE 7
`default_nettype none
`resetall
module top;
assign implicit_wire=1'b1;
initial begin
 #1; if(implicit_wire!==1 || `VALUE!=7) $fatal;
 $display("PASS"); $finish;
end
endmodule
