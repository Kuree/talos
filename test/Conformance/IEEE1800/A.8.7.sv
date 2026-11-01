// CLAUSE: Signed hexadecimal literal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
logic signed[7:0]n=8'sh80;
initial begin if(n!=-128)$fatal(1,"result"); $display("PASS");end
endmodule
