// CLAUSE: For loop with a declaration initializer
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int sum=0;
initial begin for(int i=0;i<3;i++)sum+=i;if(sum!=3)$fatal(1,"result"); $display("PASS");end
endmodule
