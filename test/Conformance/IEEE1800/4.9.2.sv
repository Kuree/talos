// CLAUSE: procedural assign rhs sensitivity
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
reg [31:0] x; int source;
initial begin
source=7; assign x=source+1; #1; if(x!=8) $fatal; source=9; #1; if(x!=10) $fatal(1,"x=%0d",x); deassign x; source=11; #1; if(x!=10) $fatal;
$display("PASS"); $finish;
end
endmodule
