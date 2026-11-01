// CLAUSE: field hiding nonvirtual binding
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; int v=1; function int f(); return v; endfunction endclass
class D extends B; int v=2; function int f(); return -v; endfunction endclass
module top;
B b; D d;
initial begin
d=new; b=d; if(d.v!=2 || b.v!=1 || d.f()!=-2 || b.f()!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
