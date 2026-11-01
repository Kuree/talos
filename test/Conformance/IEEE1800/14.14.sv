// CLAUSE: global clock
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk=0;global clocking gc@(posedge clk);endclocking
initial #1 clk=1;initial begin @($global_clock);if($time!=1)$fatal(1,"global clock event");$display("PASS");$finish;end endmodule
