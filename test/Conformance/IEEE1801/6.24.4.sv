// CLAUSE: Supply nets defined in HDL
// REQUIRES: upf
// XFAIL: *
// design.sv:3: top: simulation time 0: implicit supply
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;supply_net_type rail;
initial begin
if(!supply_on("/top/rail"))$fatal(1,"implicit supply");
$display("PASS");$finish;
end endmodule
