// CLAUSE: if chain evaluation order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int trace=0,out; function bit condition(int n); trace=trace*10+n; return n==2; endfunction
initial begin

if(condition(1)) out=1;
else if(condition(2)) out=2;
else if(condition(3)) out=3;
if(trace!=12 || out!=2) $fatal(1,"trace=%0d out=%0d",trace,out);

$display("PASS"); $finish;
end
endmodule
