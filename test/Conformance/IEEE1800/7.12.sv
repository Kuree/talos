// CLAUSE: Binding an explicit array-method iterator
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int a[2]='{4,5};int q[$];
initial begin
q=a.find(v) with(v>4);if(q.size()!=1||q[0]!=5)$fatal(1,"iterator binding");
$display("PASS");$finish;
end
endmodule
