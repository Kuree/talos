// CLAUSE: Concatenation of sized values
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit[7:0]n;
initial begin n={4'ha,4'h5};if(n!=8'ha5)$fatal(1,"result"); $display("PASS");end
endmodule
