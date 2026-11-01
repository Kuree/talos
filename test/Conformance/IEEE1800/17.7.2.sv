// CLAUSE: checker assume randomization
// XFAIL: *
// Free checker-variable randomization with assumptions is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: CHECK

checker c(input event clock);rand bit v;
a:assume property(@clock v==1);
b:assert property(@clock v==1)$display("CHECK");else $fatal;
endchecker
module top;bit clk;c inst(posedge clk);
initial begin #1;clk=1;#1;$display("PASS");$finish;end endmodule
