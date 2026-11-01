// CLAUSE: evcd size limit
// XFAIL: *
// Reaching the EVCD size limit truncates output without the required limit comment.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.evcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$comment.*[Ll]imit}}

module cell_t(output reg q=0);endmodule
module top;
wire q;cell_t dut(q);
initial begin
$dumpports(dut,"probe.evcd");$dumpportslimit(64,"probe.evcd");repeat(20)begin #1;dut.q=~dut.q;end
$display("PASS");$finish;
end
endmodule
