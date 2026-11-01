// CLAUSE: undefineall
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define X 1
`undefineall
`ifdef X
`error defined
`endif
module top;

initial begin

$display("PASS");$finish;
end
endmodule
