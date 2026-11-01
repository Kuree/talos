// CLAUSE: module header package types
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package P; typedef bit[7:0] Byte; parameter int N=3; endpackage
module child import P::*; #(parameter int W=N)(input Byte data,output Byte result); assign result=data+W; endmodule
module top; P::Byte data=7; wire[7:0] result; child u(data,result);
initial begin #1; if(result!=10 || u.W!=3) $fatal; $display("PASS"); $finish; end
endmodule
