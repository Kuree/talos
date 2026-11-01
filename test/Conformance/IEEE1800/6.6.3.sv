// CLAUSE: wired net resolution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wor a; wand b; assign a=1'bx; assign a=1'b1; assign b=1'bx; assign b=1'b0;
initial begin
#1; if(a!==1 || b!==0) $fatal(1,"a=%b b=%b",a,b);
$display("PASS"); $finish;
end
endmodule
