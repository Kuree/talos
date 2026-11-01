// CLAUSE: force net release driver
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic src,forced; wire dst; assign dst=src;
initial begin
src=0; forced=1; #1; force dst=forced; #1; if(dst!==1) $fatal; forced=0; #1; if(dst!==0) $fatal; src=1; #1; if(dst!==0) $fatal; release dst; #1; if(dst!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
