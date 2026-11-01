// CLAUSE: dynamic array foreach
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand int a[]; constraint k {a.size()==3; foreach(a[i]) a[i]==i;} endclass
module top;
C c;
initial begin
c=new; if(!c.randomize() || c.a.size()!=3) $fatal; foreach(c.a[i]) if(c.a[i]!=i) $fatal;
$display("PASS"); $finish;
end
endmodule
