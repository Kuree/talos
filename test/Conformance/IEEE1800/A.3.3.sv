// CLAUSE: Net and expression primitive terminals
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit a=1,b=0;wire y;xor g(y,a,!b);
initial begin #1;if(y!==0)$fatal(1,"result"); $display("PASS");end
endmodule
