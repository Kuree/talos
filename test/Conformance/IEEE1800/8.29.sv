// CLAUSE: dynamic array strong handles
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Obj; int value; function new(int v=0); value=v; endfunction endclass

module top; timeunit 1ns; timeprecision 1ps;
task automatic churn(input int count); Obj temporary; for(int i=0;i<count;i++) begin temporary=new(i); if(temporary.value!=i) $fatal(1,"churn payload"); temporary=null; if(i%64==0) #0; end endtask
initial begin
Obj array[]; array=new[16]; foreach(array[i]) array[i]=new(i); churn(1024); foreach(array[i]) if(array[i].value!=i) $fatal(1,"array roots"); array.delete(); if(array.size()!=0) $fatal(1,"array empty");
$display("PASS"); end endmodule
