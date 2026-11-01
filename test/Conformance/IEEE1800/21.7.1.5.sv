// CLAUSE: vcd size limit
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=probe.vcd
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{\$comment.*[Ll]imit}}

module top;
logic q=0;
initial begin
$dumpfile("probe.vcd");$dumpvars(0,q);$dumplimit(64);repeat(20)begin #1;q=~q;end
$display("PASS");$finish;
end
endmodule
