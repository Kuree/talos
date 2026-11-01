// CLAUSE: loops continue control do once
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int sum=0,n=0,hits=0,once=0,forever_count=0;
initial begin

for(int i=0; i<4; i++) begin if(i==1) continue; sum+=i; end
while(n<3) begin n++; if(n==2) continue; hits++; end
do begin once++; continue; end while(0);
forever begin forever_count++; if(forever_count==3) break; end
if(sum!=5 || n!=3 || hits!=2 || once!=1 || forever_count!=3) $fatal;

$display("PASS"); $finish;
end
endmodule
