// CLAUSE: queue pop back
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int q[$]='{4,9};int n;
initial begin
n=q.pop_back();
if(n!=9 || q.size()!=1)$fatal(1,"pop_back");
$display("PASS");$finish;
end
endmodule
