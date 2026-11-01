// CLAUSE: Binary bitwise operations preserve unknown bits
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  logic[3:0] a=4'b10xz,b=4'b0101;
  initial begin
    if((a&b)!==4'b000x)$fatal(1,"AND");
    if((a|b)!==4'b11x1)$fatal(1,"OR");
    if((a^b)!==4'b11xx)$fatal(1,"XOR");
    $display("PASS");
  end
endmodule
