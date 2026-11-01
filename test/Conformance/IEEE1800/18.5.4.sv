// CLAUSE: unique fixed array
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [1:0] a[4]; constraint k {unique {a};} endclass
module top;
C c;
initial begin
c=new; if(!c.randomize()) $fatal; foreach(c.a[i]) foreach(c.a[j]) if(i!=j && c.a[i]==c.a[j]) $fatal;
$display("PASS"); $finish;
end
endmodule
