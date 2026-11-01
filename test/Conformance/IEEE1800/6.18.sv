// CLAUSE: typedef forward class
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef class C;
class D; C c; endclass
class C; int value=7; endclass
module top; C c; D d; initial begin c=new; d=new; d.c=c; if(d.c.value!=7) $fatal; $display("PASS"); $finish; end endmodule
