// CLAUSE: Continuous access overview
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfSupplyNetT'; did you mean 'upfSupplyTypeT'?
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.4.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;upfSupplyNetT mirror;
initial begin
if(!upf_create_object_mirror("/top/VDD","/top/mirror"))$fatal(1,"mirror");
void'(supply_on("/top/VDD"));#1;
if(mirror.current_value.state!=FULL_ON)$fatal(1,"mirror value");
$display("PASS");$finish;end endmodule
