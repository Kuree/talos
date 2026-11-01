// CLAUSE: Supply states
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.2/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyStateE s;
initial begin
s=UNDETERMINED;if(OFF!=0 || FULL_ON!=1 || PARTIAL_ON!=2 || s!=3)$fatal(1,"enum");
$display("PASS");$finish;end endmodule
