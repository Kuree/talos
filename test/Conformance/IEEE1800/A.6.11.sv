// CLAUSE: Clocking block with an input skew
// XFAIL: bytecode
// Bytecode crashes when reading the clocking input.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit clk=0;logic d=1;clocking cb @(posedge clk);input #0 d;endclocking
initial begin #1;clk=1;#1;if(cb.d!==1)$fatal(1,"result"); $display("PASS");end
endmodule
