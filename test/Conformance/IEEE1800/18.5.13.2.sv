// CLAUSE: disable soft then later soft
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit[2:0] x; constraint first {soft x==3;} constraint remove {disable soft x;} constraint last {soft x inside {1,2};} endclass
module top; C c;
initial begin
c=new; repeat(4) if(!c.randomize() || !(c.x inside {1,2})) $fatal;
$display("PASS"); $finish; end
endmodule
