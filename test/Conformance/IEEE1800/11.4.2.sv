// CLAUSE: real increment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
real r,pre,post;
initial begin
r=1.25; pre=++r; post=r--; if(pre!=2.25 || post!=2.25 || r!=1.25) $fatal;
$display("PASS"); $finish;
end
endmodule
