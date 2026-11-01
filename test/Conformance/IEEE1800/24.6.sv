// CLAUSE: anonymous program
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package PK;program;function int value();return 7;endfunction endprogram endpackage
program P;initial begin if(PK::value()!=7)$fatal;$display("PASS");$finish;end endprogram
module top;P p();endmodule
