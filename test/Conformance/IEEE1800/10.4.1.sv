// CLAUSE: tri element assignment control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int src[1],dst;
initial begin
src[0]=7; dst=src[0]; if(dst!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
