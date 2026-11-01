// CLAUSE: Driver and receiver supplies
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_port_attributes"; the command is not implemented.
// Pins: -source selects by driver supply: the port attributed to AON is outside a strategy that isolates only CORE-driven ports (IEEE 1801-2018 4.6.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.6.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run a=1 b=1
// CHECK: iso a=1 b=0

module leaf(output wire a,b);assign a=1;assign b=1;endmodule
module top;
import UPF::*;
logic iso=0;wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VAON"));
#1;$display("run a=%b b=%b",a,b);
iso=1;#1;$display("iso a=%b b=%b",a,b);
$finish;
end
endmodule
