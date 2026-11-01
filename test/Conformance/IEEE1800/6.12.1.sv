// CLAUSE: real to integer rounding
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a,b; real x=1.5,y=-1.5;
initial begin
a=x; b=y; if(a!=2 || b!=-2 || int'(x)!=2 || int'(y)!=-2) $fatal(1,"a=%0d b=%0d",a,b);
$display("PASS"); $finish;
end
endmodule
