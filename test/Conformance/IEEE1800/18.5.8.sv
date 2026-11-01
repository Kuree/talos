// CLAUSE: random child handle global
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Child; rand bit [3:0] x; endclass class C; rand Child child; constraint k {child.x==5;} endclass
module top;
C c; Child saved;
initial begin
c=new; c.child=new; saved=c.child; if(!c.randomize() || c.child!==saved || c.child.x!=5) $fatal;
$display("PASS"); $finish;
end
endmodule
