// CLAUSE: function argument ordering
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit[3:0] x,y; function bit[3:0] identity(input bit[3:0] v); return v; endfunction constraint k {x==3; y==identity(x)+1;} endclass
module top; C c;
initial begin
c=new; if(!c.randomize() || c.x!=3 || c.y!=4) $fatal(1,"x=%0d y=%0d",c.x,c.y);
$display("PASS"); $finish; end
endmodule
