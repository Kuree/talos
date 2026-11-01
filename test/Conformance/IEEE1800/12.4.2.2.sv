// CLAUSE: unique if process reports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-COUNT-2: {{[uU][nN][iI][qQ][uU][eE] [iI][fF] [vV][iI][oO][lL][aA][tT][iI][oO][nN]}}
// CHECK-DAG: {{^PASS$}}

module top;function void f();unique if(1)begin end else if(1)begin end endfunction
initial f();initial f();initial begin #1;$display("PASS");$finish;end endmodule
