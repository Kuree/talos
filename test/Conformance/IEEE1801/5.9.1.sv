// CLAUSE: Effective element-list construction
// REQUIRES: upf
// XFAIL: *
// create_power_domain does not support -exclude_elements.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.9.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1'b1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a),other(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;if(a!==1 || b!==1)$fatal;
void'(supply_off("/top/VDD"));#1;if(a!==1'bx || b!==1)$fatal(1,"effective elements");
$display("PASS");$finish;
end
endmodule
