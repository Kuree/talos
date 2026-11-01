// CLAUSE: tri lhs struct one untyped
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
struct {int v;} src; int dst;
initial begin
src.v=7; '{dst}=src; if(dst!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
