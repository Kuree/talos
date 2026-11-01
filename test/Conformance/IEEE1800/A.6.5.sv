// CLAUSE: Delay and named-event control statements
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
event e;int n=0;
initial begin fork begin @e;n=7;end begin #1;->e;end join if(n!=7)$fatal(1,"result"); $display("PASS");end
endmodule
