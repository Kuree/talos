// CLAUSE: dynamic real elements
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
real a[]; real value=1.5;
initial begin
a=new[2]; a[0]=value; a[1]=value+1.0; if(a[0]!=1.5 || a[1]!=2.5) $fatal;
$display("PASS"); $finish;
end
endmodule
