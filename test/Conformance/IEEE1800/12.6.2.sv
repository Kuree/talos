// CLAUSE: pattern if filter short circuit
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {int a,b;} S; S s; int calls=0,out; function bit touch(); calls++; return 1; endfunction
initial begin

s='{1,2};
if(s matches '{a:9} &&& touch()) out=1;
if(s matches '{a:.n} &&& n==1 &&& touch()) out=2;
if(calls!=1 || out!=2) $fatal(1,"calls=%0d out=%0d",calls,out);

$display("PASS"); $finish;
end
endmodule
