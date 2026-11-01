// CLAUSE: array pattern duplicate index error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
int a[2];
initial begin
a='{0:1,0:2,default:0};
$display("PASS"); $finish;
end
endmodule
