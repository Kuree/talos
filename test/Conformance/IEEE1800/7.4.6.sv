// CLAUSE: array operations
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2]='{1,2},b[2];
initial begin
b=a;if(b!=a)$fatal(1,"aggregate assignment/equality");
$display("PASS");$finish;
end
endmodule
