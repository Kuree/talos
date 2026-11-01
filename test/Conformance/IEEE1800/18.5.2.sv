// CLAUSE: inherit override via base
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; rand bit [3:0] x; constraint k {x==1;} endclass class D extends B; constraint k {x==2;} endclass
module top;
B b; D d;
initial begin
d=new; b=d; if(!b.randomize() || d.x!=2) $fatal;
$display("PASS"); $finish;
end
endmodule
