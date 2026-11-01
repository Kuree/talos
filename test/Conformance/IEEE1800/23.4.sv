// CLAUSE: nested module lexical scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
localparam int N=7;
module child; int value; initial value=N; endmodule
child u();
initial begin #1; if(u.value!=7) $fatal; $display("PASS"); $finish; end
endmodule
