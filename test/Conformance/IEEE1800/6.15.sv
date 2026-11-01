// CLAUSE: shallow copy value properties
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Leaf; int value=3; endclass
class Item;
  static int constructors=0;
  int a[]; int q[$]; Leaf child;
  function new(); constructors++; a='{1,2}; q='{4,5}; child=new; endfunction
endclass
module top;
  Item a,b;
  initial begin
    a=new; b=new a;
    b.a[0]=99; b.q[0]=88; b.child.value=77;
    $display("original=%p %p child=%0d ctors=%0d",a.a,a.q,a.child.value,Item::constructors);
    if(a.a[0]!=1 || a.q[0]!=4 || a.child.value!=77 || Item::constructors!=1) $fatal(1,"shallow copy");
    $display("PASS"); $finish;
  end
endmodule
