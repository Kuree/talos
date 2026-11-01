// CLAUSE: buf not gates
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wire a,b;buf(a,1'b1);not(b,1'b1);
initial begin
#1;if(a!==1 || b!==0)$fatal;
$display("PASS");$finish;
end
endmodule
