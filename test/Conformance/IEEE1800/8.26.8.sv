// CLAUSE: interface method conflict single implementation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface class I; pure virtual function int f(int n=3); endclass
interface class J; pure virtual function int f(int n=3); endclass
class C implements I,J; virtual function int f(int n=3); return n+4; endfunction endclass
module top;
C c; I i; J j;
initial begin
c=new; i=c; j=c; if(i.f()!=7 || j.f()!=7 || c.f(5)!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
