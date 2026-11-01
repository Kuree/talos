// CLAUSE: Randomization
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef enum bit[3:0] {A=1,B=7,CVAL=12} E; class C; rand E x; endclass
module top; C c;
initial begin
c=new; repeat(16) if(!c.randomize() || !(c.x inside {A,B,CVAL})) $fatal(1,"enum=%0d",c.x);
$display("PASS"); $finish; end
endmodule
