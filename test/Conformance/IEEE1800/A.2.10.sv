// CLAUSE: Property declaration with a formal argument
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;bit clk=0;
property p(bit x);x;endproperty
a:assert property(@(posedge clk)p(1))$display("PASS");
initial begin #1;clk=1;#1;$finish;end
endmodule
