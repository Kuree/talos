// CLAUSE: pattern conditional bound consequent
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {int a,b;} S; S s; int out;
initial begin

s='{7,9};
out=(s matches '{a:.n} &&& n>0 ? n : -1);
if(out!=7) $fatal(1,"out=%0d",out);

$display("PASS"); $finish;
end
endmodule
