// CLAUSE: $scale optional interface
// XFAIL: *
// The optional $scale system interface is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns;timeprecision 1ns;real scaled;
initial begin
 #1;scaled=$scale(top);if(scaled!=1)$fatal(1,"scale");
$display("PASS");$finish;
end
endmodule
