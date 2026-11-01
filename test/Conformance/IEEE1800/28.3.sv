// CLAUSE: primitive array broadcast
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
logic [3:0] a=4'b1010; logic enable=0; wire [3:0] y; bufif0 g[3:0](y,a,enable);
initial begin
#1; if(y!==4'b1010) $fatal; enable=1; #1; if(y!==4'bzzzz) $fatal;
$display("PASS"); $finish;
end
endmodule
