// CLAUSE: Case-sensitive UPF names
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import UPF::*;
upfSupplyTypeT lower,upper;
initial begin
if(!supply_on("/top/Rail"))$fatal;
lower=get_supply_value("/top/rail");upper=get_supply_value("/top/Rail");
if(lower.state!=OFF || upper.state!=FULL_ON)$fatal(1,"case-sensitive identifiers");
$display("PASS");$finish;
end
endmodule
