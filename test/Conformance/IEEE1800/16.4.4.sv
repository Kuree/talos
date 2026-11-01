// CLAUSE: Disabling one labeled deferred assertion cancels only its pending report while another ass
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 1ns;
int calls=0,total=0;function automatic void record(input int value);calls++;total+=value;endfunction
initial begin
first:assert #0(1)record(1);second:assert #0(1)record(2);disable first;#1;if(calls!=1 || total!=2)$fatal(1,"calls=%0d total=%0d",calls,total);
$display("PASS");$finish;end
endmodule
