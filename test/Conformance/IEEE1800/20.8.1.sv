// CLAUSE: clog2 unsigned
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if($clog2(0)!=0 || $clog2(1)!=0 || $clog2(3)!=2 || $clog2(64'hffffffffffffffff)!=64) $fatal;
$display("PASS"); $finish;
end
endmodule
