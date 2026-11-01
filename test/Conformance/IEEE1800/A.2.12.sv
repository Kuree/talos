// CLAUSE: Let declaration with formal arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
let add(x,y)=x+y;
initial begin if(add(3,4)!=7)$fatal(1,"result"); $display("PASS");end
endmodule
