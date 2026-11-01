// CLAUSE: structure real literal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 6.25: type parameters on classes (typedef in a virtual class) and modules specialise per instantiation with the right width and values.
// CHECK-DAG: W 8 64 x=fff y=-1 bits=12
// CHECK-DAG: top.m8 bits=8 v=ff
// CHECK-DAG: top.m10 bits=10 v=3ff

virtual class C #(parameter type T = int);
  typedef T elem_t;
  static function int width(); return $bits(T); endfunction
endclass
module m #(parameter type T = int) ();
  T v;
  initial begin v = '1; #1 $display("%m bits=%0d v=%0h", $bits(v), v); end
endmodule
module top;
  C#(logic [11:0])::elem_t x = 12'hfff;  C#(shortint)::elem_t y = -1;
  m #(.T(byte)) m8();  m #(.T(logic [9:0])) m10();
  initial $display("W %0d %0d x=%h y=%0d bits=%0d", C#(byte)::width(), C#(longint)::width(), x, y, $bits(C#(logic [11:0])::elem_t));
endmodule
