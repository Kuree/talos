// CLAUSE: inline nonrand variable
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; bit [3:0] x; rand bit [3:0] y; constraint k {int'(x)+int'(y)==7;} endclass
module top;
C c;
initial begin
c=new; c.y=3; if(!c.randomize(x) || c.x!=4 || c.y!=3) $fatal;
$display("PASS"); $finish;
end
endmodule
