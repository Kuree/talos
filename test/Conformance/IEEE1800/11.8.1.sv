// CLAUSE: signed part select
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [1:0] value=3;
initial begin

$display("CAST=%0d",int'(value));
if(int'(value)!=3) $fatal(1,"CAST_RESULT");
$display("PASS"); $finish;
end endmodule
