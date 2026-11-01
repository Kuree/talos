// CLAUSE: tri conflict release
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic a=0,b=1; tri n; assign n=a; assign n=b;
initial begin
#1; if(n!==1'bx) $fatal; a=1'bz; #1; if(n!==1) $fatal; b=1'bz; #1; if(n!==1'bz) $fatal; a=0; #1; if(n!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
