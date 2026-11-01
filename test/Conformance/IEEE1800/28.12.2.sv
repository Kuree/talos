// CLAUSE: An uncertain enable creates0-orZ/1-orZ; combining each with a matching definite strong dri
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic enable=1'bx; wire a,b,c,d;
bufif1 g0(a,1'b0,enable),g1(b,1'b1,enable); notif0 h0(c,1'b1,enable),h1(d,1'b0,enable);
assign a=0; assign b=1; assign c=0; assign d=1;
initial begin
#1; if(a!==0 || b!==1 || c!==0 || d!==1) $fatal(1,"a=%b b=%b c=%b d=%b",a,b,c,d); enable=1'bz; #1; if(a!==0 || b!==1 || c!==0 || d!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
