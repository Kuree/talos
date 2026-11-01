// CLAUSE: evcd driver strength
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.evcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{^pu[[:space:]]+[0-7][[:space:]]+6[[:space:]]+<0}}

module cell_t(inout wire q);assign(weak0,weak1)q=0;endmodule
module top;wire q;assign(strong0,strong1)q=1;cell_t dut(q);
initial begin $dumpports(dut,"probe.evcd");#2;$display("PASS");$finish;end endmodule
