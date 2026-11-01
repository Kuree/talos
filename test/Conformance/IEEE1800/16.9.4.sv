// CLAUSE: global sampled function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk,signal=1;global clocking g@(posedge clk);endclocking
assert property(@(posedge clk) $time>1 |-> $past_gclk(signal)==1);
initial begin #1;clk=1;#1;clk=0;#1;clk=1;#1;$display("PASS");$finish;end endmodule
