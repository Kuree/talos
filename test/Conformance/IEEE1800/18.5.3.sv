// CLAUSE: distribution zero excluded
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [1:0] x; constraint k {x dist {0:=0,[1:3]:/1};} endclass
module top;
C c;
initial begin
c=new; repeat(8) if(!c.randomize() || c.x==0) $fatal;
$display("PASS"); $finish;
end
endmodule
