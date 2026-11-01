// CLAUSE: if mixed unknown truth
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a,b,c;
initial begin

if(4'bx001) a=1; else a=2;
if(4'bx000) b=1; else b=2;
if(4'bzzzz) c=1; else c=2;
if(a!=1 || b!=2 || c!=2) $fatal(1,"a=%0d b=%0d c=%0d",a,b,c);

$display("PASS"); $finish;
end
endmodule
