// CLAUSE: Queue push_back appends one element
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int q[$]='{1};
initial begin
q.push_back(2);
if(q.size()!=2 || q[0]!==1 || q[1]!==2)$fatal;
$display("PASS");
end
endmodule
