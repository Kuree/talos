// CLAUSE: Derived sequential property finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit clk=0;int hits=0;
always #1 clk=~clk;

a:assert property(@(posedge clk) disable iff($time>3) strong(1 ##1 1))hits++;else $fatal(1,"assertion");
initial begin  #8;if(hits<1)$fatal(1,"missing match");$display("PASS");$finish;end
endmodule
