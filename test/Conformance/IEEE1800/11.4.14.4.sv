// CLAUSE: streaming dynamic greedy unpack
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
byte unsigned a[],b[],tail;
initial begin
a=new[1]; a[0]=0; b=new[1]; b[0]=0; {>>{a,b,tail}}=32'h11223344; if(a.size()!=3 || b.size()!=0 || a[0]!=8'h11 || a[1]!=8'h22 || a[2]!=8'h33 || tail!=8'h44) $fatal(1,"sizes=%0d,%0d tail=%h",a.size(),b.size(),tail);
$display("PASS"); $finish;
end
endmodule
