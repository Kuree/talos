// CLAUSE: unique case process reports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-COUNT-2: {{[uU][nN][iI][qQ][uU][eE] [cC][aA][sS][eE] [vV][iI][oO][lL][aA][tT][iI][oO][nN]}}
// CHECK-DAG: {{^PASS$}}

module top;function void f();unique case(1)1:begin end 1:begin end endcase endfunction
initial f();initial f();initial begin #1;$display("PASS");$finish;end endmodule
