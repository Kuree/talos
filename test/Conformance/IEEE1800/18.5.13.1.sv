// CLAUSE: soft derived priority
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; rand bit[2:0] x; constraint one {soft x==1;} endclass class C extends B; constraint two {soft x==2;} endclass
module top; C c;
initial begin
c=new; repeat(4) if(!c.randomize() || c.x!=2) $fatal(1,"x=%0d",c.x);
$display("PASS"); $finish; end
endmodule
