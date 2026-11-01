// CLAUSE: mintypmax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --timing=max -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int n;
initial begin
n=(1:2:3);if(n!=3)$fatal(1,"mintypmax choice");
$display("PASS");$finish;
end
endmodule
