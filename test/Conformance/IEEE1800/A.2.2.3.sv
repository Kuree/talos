// CLAUSE: Delay on a continuous assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit a=0;wire y;assign #2 y=a;
initial begin #3;a=1;#1;if(y!==0)$fatal(1,"result");#2;if(y!==1)$fatal(1,"result"); $display("PASS");end
endmodule
