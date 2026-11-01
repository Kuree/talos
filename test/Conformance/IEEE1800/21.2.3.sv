// CLAUSE: continuous monitor
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: MON=0
// CHECK-DAG: MON=1

module top;
int n=0;
initial begin
$monitor("MON=%0d",n);#1;n=1;#1;
$display("PASS");$finish;
end
endmodule
