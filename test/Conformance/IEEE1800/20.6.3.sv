// CLAUSE: range query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[7:2]a;
initial begin
if($left(a)!=7 || $right(a)!=2 || $low(a)!=2 || $high(a)!=7 || $increment(a)!=1)$fatal;
$display("PASS");$finish;
end
endmodule
