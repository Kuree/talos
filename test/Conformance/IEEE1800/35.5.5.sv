// CLAUSE: Imported functions return each permitted result type; a packed vector result is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/35.5.5/illegal.sv -o %t.bad.exe
// RUN: %clang -c -fPIC %S/Inputs/35.5.5/dpi.c -I%resource_dir/include -o %t.dpi.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.dpi.o -o %t.exe
// RUN: %t.exe
// DIAG: 'bit[7:0]' is not a valid return type for a DPI subroutine
// CHECK: byte -5 shortint -300{{$}}
// CHECK-NEXT: int 70000 longint 1099511627776{{$}}
// CHECK-NEXT: real 2.50 shortreal 0.25{{$}}
// CHECK-NEXT: chandle 1 string hello{{$}}
// CHECK-NEXT: bit 1 logic x{{$}}
// CHECK-NEXT: void calls 1{{$}}

// 35.5.5: every result type the clause lists comes back with a value a default-initialized result could not give.
module top;
  import "DPI-C" function byte r_byte();
  import "DPI-C" function shortint r_shortint();
  import "DPI-C" function int r_int();
  import "DPI-C" function longint r_longint();
  import "DPI-C" function real r_real();
  import "DPI-C" function shortreal r_shortreal();
  import "DPI-C" function chandle r_chandle();
  import "DPI-C" function string r_string();
  import "DPI-C" function bit r_bit();
  import "DPI-C" function logic r_logic();
  import "DPI-C" function void r_void();
  import "DPI-C" function int r_calls();
  chandle h;
  initial begin
    $display("byte %0d shortint %0d", r_byte(), r_shortint());
    $display("int %0d longint %0d", r_int(), r_longint());
    $display("real %0.2f shortreal %0.2f", r_real(), r_shortreal());
    h = r_chandle();
    $display("chandle %b string %s", h != null, r_string());
    $display("bit %b logic %b", r_bit(), r_logic());
    r_void();
    $display("void calls %0d", r_calls());
    $finish;
  end
endmodule
