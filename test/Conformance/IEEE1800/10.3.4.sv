// CLAUSE: continuous highz pair error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
wire dst; assign (highz1,highz0) dst=1'b1;
initial begin

$display("PASS"); $finish;
end
endmodule
