// CLAUSE: Packed and unpacked declaration ranges
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit[3:1]a[2:0];
initial begin a[1]=3'b101;if($bits(a)!=9 || a[1]!=5)$fatal(1,"result"); $display("PASS");end
endmodule
