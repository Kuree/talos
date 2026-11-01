// CLAUSE: Changing the mode of a static constraint affects that constraint in every object of the de
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit x; static constraint k {x==0;} endclass
module top; initial begin
C a,b; a=new; b=new; a.k.constraint_mode(0); if(b.k.constraint_mode()!=0 || !a.randomize() with {x==1;} || !b.randomize() with {x==1;}) $fatal; b.k.constraint_mode(1); if(a.k.constraint_mode()!=1 || !a.randomize() || !b.randomize() || a.x!=0 || b.x!=0) $fatal;
$display("PASS"); $finish; end endmodule
