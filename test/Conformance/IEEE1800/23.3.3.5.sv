// CLAUSE: unpacked instance array direction
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child(input bit data,output wire result); assign result=data; endmodule
module top;
bit data[3:2]='{1,0}; wire result[9:8];
child u[0:1](data,result);
initial begin #1; if(result[9]!==1 || result[8]!==0 || u[0].data!=1 || u[1].data!=0) $fatal; $display("PASS"); $finish; end
endmodule
