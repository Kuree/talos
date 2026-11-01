// CLAUSE: object seed independent process rng
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit[7:0] x,y; endclass
module top; C c,other;
initial begin
c=new; other=new; c.srandom(99); other.srandom(99);
 repeat(8) begin if(!c.randomize()) $fatal; void'($urandom); if(!other.randomize() || c.x!=other.x || c.y!=other.y) $fatal; end
$display("PASS"); $finish; end
endmodule
