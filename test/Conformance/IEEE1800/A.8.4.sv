// CLAUSE: Selected bit used as a primary expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit[7:0]n=8'h80;
initial begin if(n[7]!==1)$fatal(1,"result"); $display("PASS");end
endmodule
