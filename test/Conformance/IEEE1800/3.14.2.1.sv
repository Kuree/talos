// CLAUSE: timescale
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
module top;initial begin #0.001;if($realtime!=0.001)$fatal(1,"timescale");$display("PASS");$finish;end endmodule
