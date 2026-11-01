// CLAUSE: sequence or named
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit clk; event e; sequence s; @(posedge clk) 0; endsequence
initial begin
@(s or e);
$display("PASS"); $finish;
end
initial begin #1; ->e; #1; $fatal(1,"named event not received"); end
endmodule
