// CLAUSE: random real singleton
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand real x; constraint k {x==1.5;} endclass
module top;
C c;
initial begin
c=new; if(!c.randomize() || c.x!=1.5) $fatal;
$display("PASS"); $finish;
end
endmodule
