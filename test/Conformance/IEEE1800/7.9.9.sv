// CLAUSE: assoc copy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int],b[int];
initial begin
a[3]=7;b=a;a[3]=9;if(b[3]!=7)$fatal(1,"associative copy");
$display("PASS");$finish;
end
endmodule
