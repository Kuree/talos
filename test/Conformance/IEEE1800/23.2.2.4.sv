// CLAUSE: default input definition scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child #(parameter int N=7)(input int data=N,output int result); assign result=data; endmodule
module top;
localparam int N=9; int result;
child u(.result(result));
initial begin #1; if(result!=7) $fatal(1,"result=%0d",result); $display("PASS"); $finish; end
endmodule
