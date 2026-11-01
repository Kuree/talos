// CLAUSE: optional E.2 behavior
// XFAIL: *
// The optional directive does not produce the required observed default/range behavior.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`default_decay_time 2
module top;timeunit 1ns;timeprecision 1ns;trireg q;bit en=1;
bufif1 b(q,1'b0,en);
initial begin #1;en=0;#1;if(q!==0)$fatal(1,"charge lost early");
#2;if(q!==1'bx)$fatal(1,"default decay ignored");$display("PASS");$finish;end
endmodule
