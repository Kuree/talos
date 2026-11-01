// CLAUSE: sequence iff
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit clk; sequence s; @(posedge clk) 1; endsequence
initial begin
@(s iff 1);
$display("PASS"); $finish;
end
initial begin #1; clk=1; #1; $fatal(1,"no endpoint"); end
endmodule
