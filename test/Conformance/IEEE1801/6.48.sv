// CLAUSE: set_port_attributes
// SINCE: 0.2.0
// REQUIRES: upf
// Pins: in a block's own UPF context, output receiver assumptions select
// different-PG isolation. Equivalent PG roots leave a unchanged despite the
// supply sets' different identities and implicit bias roots (6.48/6.45).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.48/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run a=1 b=1
// CHECK: iso a=1 b=0

module leaf(input logic iso,output logic a,b);
  always_comb begin a=1; b=1; end
endmodule
module top;
import UPF::*;
logic iso=0;wire a,b;leaf dut(iso,a,b);
initial begin
if (!supply_on("/top/dut/CORE.power") || !supply_on("/top/dut/CORE.ground",0.0) ||
    !supply_on("/top/dut/AON.power") || !supply_on("/top/dut/AON.ground",0.0))
  $fatal(1,"supplies");
#1;$display("run a=%b b=%b",a,b);
iso=1;#1;$display("iso a=%b b=%b",a,b);
$finish;
end
endmodule
