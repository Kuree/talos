// CLAUSE: Program instance with parameter override
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

program P #(parameter N=7);initial begin if(N!=3)$fatal;$display("PASS");end endprogram
module top;P #(3)p();endmodule
