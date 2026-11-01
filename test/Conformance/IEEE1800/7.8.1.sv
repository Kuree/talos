// CLAUSE: wildcard index
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[*];
initial begin
a[64'h100000000]=7;if(a[64'h100000000]!=7)$fatal(1,"wildcard integral index");
$display("PASS");$finish;
end
endmodule
