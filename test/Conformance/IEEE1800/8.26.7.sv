// CLAUSE: partial interface implementation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface class I;pure virtual function int f();pure virtual function int g();endclass
virtual class A implements I;virtual function int f();return 1;endfunction pure virtual function int g();endclass
class C extends A;virtual function int g();return 2;endfunction endclass
module top;C c;I i;initial begin c=new;i=c;if(i.f()+i.g()!=3)$fatal(1,"partial implementation");$display("PASS");$finish;end endmodule
