// CLAUSE: deferred assertion reports from independent processes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 1ns;
int calls=0,total=0;function automatic void record(input int value);calls++;total+=value;endfunction
task automatic issue(input int value);assert #0(1)record(value);endtask
initial begin
fork issue(7);issue(9);join #1;if(calls!=2 || total!=16)$fatal(1,"calls=%0d total=%0d",calls,total);
$display("PASS");$finish;end
endmodule
