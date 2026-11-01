// CLAUSE: singleton constraint
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x; constraint c {x==7;} endclass
module top;
C c;
initial begin
c=new; repeat(4) if(!c.randomize() || c.x!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
