// CLAUSE: rand mode state
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x,y; constraint k {x==3; y==7;} endclass
module top;
C c;
initial begin
c=new; c.x=3; c.x.rand_mode(0); if(c.x.rand_mode()!=0 || !c.randomize() || c.x!=3 || c.y!=7) $fatal; c.x.rand_mode(1); if(c.x.rand_mode()!=1 || !c.randomize() || c.x!=3) $fatal;
$display("PASS"); $finish;
end
endmodule
