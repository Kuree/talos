// CLAUSE: task disable fork uses caller
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 1ns;
int child=0,unrelated=0;task automatic stop_children();disable fork;endtask
initial begin
fork begin #5;child=1;end join_none #1;stop_children();#5;if(child!=0 || unrelated!=1)$fatal;
$display("PASS");$finish;end
initial begin #2;unrelated=1;end
endmodule
