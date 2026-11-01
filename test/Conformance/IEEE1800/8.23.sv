// CLAUSE: The :: operator reaches static class members and nested classes; bare outer instance access is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.23/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: invalid use of non-static class property 'value' from nested class 'Inner'
// CHECK: bin 123{{$}}
// CHECK-NEXT: hex 66{{$}}
// CHECK-NEXT: static 3{{$}}
// CHECK-NEXT: nested 11 13 1214{{$}}

// 8.23: Base::bin and the variable bin stay distinct, and a nested class reaches outer locals only through :: or a handle.
class Base;
  typedef enum {bin, oct, dec, hex} radix;
  static int count = 2;
  static function string print(radix r, integer n);
    return $sformatf("%s %0d", r.name(), n);
  endfunction
endclass
class Outer;
  int outerProp;
  local int outerLocalProp;
  static int outerStaticProp;
  static local int outerLocalStaticProp;
  class Inner;
    function void innerMethod(Outer h);
      outerStaticProp = 11;
      outerLocalStaticProp = 12;
      h.outerProp = 13;
      h.outerLocalProp = 14;
    endfunction
  endclass
  function int locals();
    return outerLocalStaticProp * 100 + outerLocalProp;
  endfunction
endclass
module top;
  int bin = 123;
  Base b;
  Outer o;
  Outer::Inner i;
  initial begin
    b = new;
    $display("%s", b.print(Base::bin, bin));
    $display("%s", Base::print(Base::hex, 66));
    Base::count++;
    $display("static %0d", Base::count);
    o = new;
    i = new;
    i.innerMethod(o);
    $display("nested %0d %0d %0d", Outer::outerStaticProp, o.outerProp, o.locals());
    $finish;
  end
endmodule
