// CLAUSE: checker function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: CHECK

checker c(input event clock);function bit f();return 1;endfunction
a:assert property(@clock f())$display("CHECK");else $fatal;
endchecker
module top;bit clk;c inst(posedge clk);
initial begin #1;clk=1;#1;$display("PASS");$finish;end endmodule
