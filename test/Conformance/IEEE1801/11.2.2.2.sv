// CLAUSE: upfSupplyTypeT
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2.2/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyTypeT s;
initial begin
s='{FULL_ON,-7};if($bits(s)!=64 || s.voltage!=-7)$fatal(1,"layout");
$display("PASS");$finish;end endmodule
