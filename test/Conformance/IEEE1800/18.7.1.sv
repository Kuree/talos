// CLAUSE: inline local scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x; endclass
module top;
C c; int x;
initial begin
c=new; x=9; if(!c.randomize() with {x==local::x;} || c.x!=9 || x!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
