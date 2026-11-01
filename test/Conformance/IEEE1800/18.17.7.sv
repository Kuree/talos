// CLAUSE: A nonvoid production returns its value to its triggering production code block.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; initial begin
automatic int seen=0; randsequence(main) main:value {seen=value;}; int value:{return 1;}; endsequence if(seen!=1) $fatal(1,"return value");
$display("PASS"); end endmodule
