// CLAUSE: Bitwise operator preserves four-state results
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
logic[3:0]a=4'b10xz;
initial begin if((a & 4'b0101)!==4'b000x)$fatal(1,"result"); $display("PASS");end
endmodule
