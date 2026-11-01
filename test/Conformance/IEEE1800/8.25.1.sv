// CLAUSE: The :: operator selects class parameter specializations; unadorned use outside the class is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.25.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot refer to generic class with '::' without providing parameter assignments
// CHECK: 1 3 5{{$}}
// CHECK-NEXT: typedef 1{{$}}
// CHECK-NEXT: inside 7 out of block 13{{$}}
// CHECK-NEXT: type 8{{$}}
// CHECK-NEXT: handle 5{{$}}

// 8.25.1: inside the class C::p means this specialization's p, not the default one, and not the local p.
class C #(int p = 1, type T = int);
  parameter int q = 5;
  static function int t();
    int p = 9;
    return C::p;
  endfunction
  extern static function int u();
endclass
function int C::u();
  return C::q + C::p;
endfunction
typedef C T_default;
module top;
  T_default obj;
  initial begin
    $display("%0d %0d %0d", C#()::p, C#(3)::p, C#()::q);
    $display("typedef %0d", T_default::p);
    $display("inside %0d out of block %0d", C#(7)::t(), C#(8)::u());
    $display("type %0d", $bits(C#(.T(byte))::T));
    obj = new;
    $display("handle %0d", obj.q);
    $finish;
  end
endmodule
