// CLAUSE: soft inline override
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x; constraint k {soft x==1;} endclass
module top;
C c;
initial begin
c=new; if(!c.randomize() with {x==2;} || c.x!=2) $fatal; if(!c.randomize() || c.x!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
