// CLAUSE: Clock normalization ignores values between assertion ticks
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;bit clk=0,a=1;int passes=0;
assert property(@(posedge clk)a)passes++;else $fatal(1,"clocked assertion");
initial begin #1;a=0;#1;a=1;#1;clk=1;#1;if(passes!=1)$fatal(1,"clock normalization");$display("PASS");$finish;end endmodule
