// CLAUSE: Drive strengths resolve competing net drivers
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
wire n;assign(weak0,weak1)n=1;assign(strong0,strong1)n=0;
initial begin
#1;if(n!==0)$fatal(1,"net strength");
$display("PASS");$finish;
end
endmodule
