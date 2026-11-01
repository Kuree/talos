// CLAUSE: Sequential order after joining parallel statements
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int x,y,z;
initial begin
fork x=1;y=2;join z=x+y;if(z!=3)$fatal(1,"block grouping");
$display("PASS");$finish;
end
endmodule
