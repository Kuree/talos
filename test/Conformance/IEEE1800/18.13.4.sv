// CLAUSE: object rng state restore
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit[7:0] x,y; endclass
module top; C c; string state; bit[15:0] expected[8];
initial begin
c=new; state=c.get_randstate();
 foreach(expected[i]) begin if(!c.randomize()) $fatal; expected[i]={c.x,c.y}; end
 c.set_randstate(state);
 foreach(expected[i]) if(!c.randomize() || {c.x,c.y}!=expected[i]) $fatal(1,"restore index=%0d",i);
$display("PASS"); $finish; end
endmodule
