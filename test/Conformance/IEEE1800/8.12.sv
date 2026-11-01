// CLAUSE: shallow copy value properties
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Base; virtual function int get(); return 1; endfunction endclass
class Derived extends Base;
  int value=7;
  virtual function int get(); return value; endfunction
endclass
module top;
  Base a,b; Derived d;
  initial begin
    d=new; a=d; b=new a; d.value=9;
    if(a.get()!=9 || b.get()!=7 || a==b) $fatal(1,"polymorphic copy a=%0d b=%0d",a.get(),b.get());
    $display("PASS"); $finish;
  end
endmodule
