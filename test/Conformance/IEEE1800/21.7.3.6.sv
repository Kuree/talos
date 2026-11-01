// CLAUSE: evcd close keyword
// XFAIL: *
// The extended VCD file omits the required $vcdclose keyword.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.evcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$vcdclose[[:space:]]+#[0-9]+[[:space:]]+\$end}}

module cell_t(output reg q=0);endmodule
module top;
wire q;cell_t dut(q);
initial begin
$dumpports(dut,"probe.evcd");#2;
$display("PASS");$finish;
end
endmodule
