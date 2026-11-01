// CLAUSE: constraint if else
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class R;rand int x,y;constraint c {x==1;if(x==1)y==2;else y==3;}endclass
module top;
R r;
initial begin
r=new;if(!r.randomize() || r.y!=2)$fatal;
$display("PASS");$finish;
end
endmodule
