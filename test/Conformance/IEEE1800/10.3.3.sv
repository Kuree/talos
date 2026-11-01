// CLAUSE: continuous inertial cancel
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic src; wire dst; assign #3 dst=src;
initial begin
src=0; #4; if(dst!==0) $fatal; src=1; #1; src=0; #4; if(dst!==0) $fatal(1,"pulse not cancelled: %b",dst); src=1; #4; if(dst!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
