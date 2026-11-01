// CLAUSE: Sequential UDP rows and state-hold symbol
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

primitive latch(q,en,d);output q;reg q;input en,d;initial q=0;
table 1 0:?:0;1 1:?:1;0 ?:?:-;endtable endprimitive
module top;
bit en=0,d=1;wire q;latch u(q,en,d);
initial begin #1;en=1;#1;if(q!==1)$fatal(1,"result");en=0;d=0;#1;if(q!==1)$fatal(1,"result"); $display("PASS");end
endmodule
