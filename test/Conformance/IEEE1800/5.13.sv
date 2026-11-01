// CLAUSE: method optional parentheses
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int q[$]='{1};
initial begin
if(q.size!=1||q.size()!=1)$fatal(1,"built-in method syntax");
$display("PASS");$finish;
end
endmodule
