// CLAUSE: equal charge conflict
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
trireg(medium) a,b; bit enable=1,joined=0; assign a=enable?1'b0:1'bz; assign b=enable?1'b1:1'bz;
tranif1 link(a,b,joined);
initial begin
#1; enable=0; #1; joined=1; #1; if(a!==1'bx || b!==1'bx) $fatal(1,"a=%b b=%b",a,b);
$display("PASS"); $finish;
end
endmodule
