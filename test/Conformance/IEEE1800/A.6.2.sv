// CLAUSE: Procedural block with a blocking assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit a=0,b;always_comb b=a;
initial begin a=1;#1;if(b!==1)$fatal(1,"result"); $display("PASS");end
endmodule
