// CLAUSE: A typed constructor call builds the named subclass with its arguments; unrelated types are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.8/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: value of type 'B' cannot be assigned to type 'A'
// CHECK: D{{$}}
// CHECK-NEXT: cast 1 arg 7{{$}}
// CHECK-NEXT: E8 cast 1 x 5{{$}}

// 8.8: the object's type comes from the prefix, not the target, which virtual dispatch and $cast both show.
class C;
  virtual function string name();
    return "C";
  endfunction
endclass
class D extends C;
  int arg;
  function new(int a = 0);
    arg = a;
  endfunction
  virtual function string name();
    return "D";
  endfunction
endclass
class E #(type T = int) extends C;
  T x;
  function new(T x_init);
    super.new();
    x = x_init;
  endfunction
  virtual function string name();
    return $sformatf("E%0d", $bits(T));
  endfunction
endclass
module top;
  C c;
  D d;
  E #(byte) e;
  initial begin
    c = D::new;
    $display("%s", c.name());
    c = D::new(7);
    $display("cast %0d arg %0d", $cast(d, c), d.arg);
    c = E #(.T(byte))::new(.x_init(5));
    $display("%s cast %0d x %0d", c.name(), $cast(e, c), e.x);
    $finish;
  end
endmodule
