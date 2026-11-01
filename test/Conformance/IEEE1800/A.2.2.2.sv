// CLAUSE: Strength pair on a net assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
tri q;assign (strong1,weak0)q=1'b1;assign(weak1,weak0)q=1'b0;
initial begin #1;if(q!==1)$fatal(1,"result"); $display("PASS");end
endmodule
