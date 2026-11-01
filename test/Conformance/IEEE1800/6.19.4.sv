// CLAUSE: enum arithmetic
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef enum int{A=2,B=3}E;E e=B;
initial begin
if(e+A!=5)$fatal(1,"enum arithmetic");
$display("PASS");$finish;
end
endmodule
