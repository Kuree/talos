// CLAUSE: real math
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if($sqrt(4.0)!=2.0 || $hypot(3.0,4.0)!=5.0 || $floor(-1.25)!=-2.0 || $ceil(-1.25)!=-1.0 || $pow(2.0,3.0)!=8.0) $fatal;
$display("PASS"); $finish;
end
endmodule
