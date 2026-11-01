// CLAUSE: procedural boolean control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit clk;
initial assert property(@(posedge clk) 1'b1);
initial begin #1; clk=1; #1; clk=0; #1; clk=1; #1; $display("PASS"); $finish; end
endmodule
