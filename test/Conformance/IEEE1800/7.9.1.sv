// CLAUSE: assoc count
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int];
initial begin
a[3]=1;if(a.num()!=1||a.size()!=1)$fatal(1,"associative count");
$display("PASS");$finish;
end
endmodule
