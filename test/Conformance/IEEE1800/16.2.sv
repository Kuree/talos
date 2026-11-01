// CLAUSE: immediate assertion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int result=0;
initial begin
assert(1)result=7;else $fatal;
if(result!=7)$fatal;
$display("PASS");$finish;
end
endmodule
