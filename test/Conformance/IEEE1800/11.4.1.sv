// CLAUSE: compound index evaluate once
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2],i;
initial begin
a[0]=3; a[1]=9; i=0; a[i++] += 2; if(i!=1 || a[0]!=5 || a[1]!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
