// CLAUSE: Error handling
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a command failure is a Tcl error that catch sees, and the failed command leaves no partial object (IEEE 1801-2018 5.11).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.11/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: caught=1
// CHECK-DAG: failed=0
// CHECK-DAG: UPF supply control failed for /top/VDD

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
initial begin
$display("caught=%b",supply_on("/top/caught"));
$display("failed=%b",supply_on("/top/VDD"));
$finish;
end
endmodule
