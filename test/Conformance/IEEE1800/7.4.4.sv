// CLAUSE: multidimensional array
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int m[2][3];
initial begin
m[1][2]=7;if(m[1][2]!=7||$size(m,2)!=3)$fatal(1,"multidimensional array");
$display("PASS");$finish;
end
endmodule
