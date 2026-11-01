// CLAUSE: Explicit strength on a pull-up primitive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;tri y;pullup(pull1)g(y);assign(weak1,weak0)y=1'b0;
initial begin #1;if(y!==1)$fatal;$display("PASS");end endmodule
