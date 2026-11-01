// CLAUSE: trireg decay
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic en=1;trireg(small)#(0,0,3)n;bufif1 g(n,1'b1,en);
initial begin
#1;en=0;#1;if(n!==1)$fatal;#3;if(n!==1'bx)$fatal;
$display("PASS");$finish;
end
endmodule
