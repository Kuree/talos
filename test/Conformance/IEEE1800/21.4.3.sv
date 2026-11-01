// CLAUSE: Memory files traverse unpacked indices from low to high
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  logic[7:0] mem[1:0][2:1];
  initial begin
    $readmemh("data.hex",mem);
    if(mem[0][1]!==8'h01 || mem[0][2]!==8'h02 ||
       mem[1][1]!==8'h03 || mem[1][2]!==8'h04)$fatal(1,"memory order");
    $display("PASS");
  end
endmodule
