// CLAUSE: One implementation satisfies identical interface methods
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface class A;pure virtual function int f();endclass
interface class B;pure virtual function int f();endclass
class C implements A,B;virtual function int f();return 7;endfunction endclass
module top;C c;A a;B b;initial begin c=new;a=c;b=c;if(a.f()!=7||b.f()!=7)$fatal(1,"merged methods");$display("PASS");$finish;end endmodule
