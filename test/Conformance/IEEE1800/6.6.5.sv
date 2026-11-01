// CLAUSE: tri pull weak and strong override
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit strong_enable=0; tri0 a; tri1 b;
assign(weak1,weak0) a=1; assign(weak1,weak0) b=0;
assign(strong1,strong0) a=strong_enable?1'b1:1'bz;
assign(strong1,strong0) b=strong_enable?1'b0:1'bz;
initial begin
#1; if(a!==0 || b!==1) $fatal; strong_enable=1; #1; if(a!==1 || b!==0) $fatal; strong_enable=0; #1; if(a!==0 || b!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
