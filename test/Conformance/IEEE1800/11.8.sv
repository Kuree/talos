// CLAUSE: Assignment context preserves arithmetic carry
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
logic[7:0]a=255,b=1;logic[8:0]sum;
initial begin
sum=a+b;if(sum!=256)$fatal(1,"expression context");
$display("PASS");$finish;
end
endmodule
