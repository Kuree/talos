// CLAUSE: evcd off on
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.evcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$dumpportsoff}}
// FILE0-DAG: {{\$dumpportson}}

module cell_t(output reg q=0);endmodule
module top;
wire q;cell_t dut(q);
initial begin
$dumpports(dut,"probe.evcd");#1;$dumpportsoff("probe.evcd");dut.q=1;#1;$dumpportson("probe.evcd");#1;
$display("PASS");$finish;
end
endmodule
