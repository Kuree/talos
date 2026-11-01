// CLAUSE: Optional utilities
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;logic[7:0]m[0:1];initial begin
$sreadmemh(m,0,1,"12 34");if(m[0]!==8'h12 || m[1]!==8'h34)$fatal(1,"memory strings");$display("PASS");$finish;end endmodule
