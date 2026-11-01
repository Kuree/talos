// CLAUSE: array queries
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2:4];
initial begin
if($dimensions(a)!=2 || $unpacked_dimensions(a)!=1 || $size(a)!=3)$fatal;
$display("PASS");$finish;
end
endmodule
