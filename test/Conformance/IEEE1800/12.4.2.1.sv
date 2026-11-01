// CLAUSE: unique if overlap first
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value=2,out;
initial begin

unique if(value>0) out=1; else if(value<9) out=2;
#1; if(out!=1) $fatal;

$display("PASS"); $finish;
end
endmodule
