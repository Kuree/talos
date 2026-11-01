// CLAUSE: Parallel branches joined by a sequential block
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n=0;
initial begin fork begin #1;n++;end begin #2;n++;end join if(n!=2)$fatal(1,"result"); $display("PASS");end
endmodule
