// CLAUSE: asynchronous pla
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[1:2]mem[1:1];logic[1:2]a;logic[1:1]y;
initial begin
mem[1]=2'b11;a=2'b10;$async$and$array(mem,a,y);#1;if(y!==0)$fatal;a=2'b11;#1;if(y!==1)$fatal;
$display("PASS");$finish;
end
endmodule
