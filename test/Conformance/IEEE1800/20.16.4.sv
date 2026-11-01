// CLAUSE: pla personality formats
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[1:1]array_mem[1:1],plane_mem[1:1],a,y,z;
initial begin
array_mem[1]=1;plane_mem[1]=0;a=1;$sync$and$array(array_mem,a,y);$sync$and$plane(plane_mem,a,z);if(y!==1 || z!==0)$fatal;
$display("PASS");$finish;
end
endmodule
