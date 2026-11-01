// CLAUSE: A whole-vector operand includes every bit
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;logic[7:0]a=8'h81,b;
initial begin b=a;if(b!==8'h81)$fatal(1,"whole operand");$display("PASS");$finish;end endmodule
