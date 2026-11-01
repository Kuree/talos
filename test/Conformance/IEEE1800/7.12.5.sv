// CLAUSE: map fixed min
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[1]='{7}; int b[1];
initial begin
b=a.map(it) with(it.index); if(b[0]!=0) $fatal;
$display("PASS"); $finish;
end
endmodule
