// CLAUSE: concat select lvalue error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
bit a,b;
initial begin
{a,b}[0]=1;
$display("PASS"); $finish;
end
endmodule
