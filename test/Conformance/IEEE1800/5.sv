// CLAUSE: Comments, identifiers, numbers and strings read as specified; a digit outside the base is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: expected binary digit
// CHECK: 1 2{{$}}
// CHECK-NEXT: 1x0z1010 00ab{{$}}
// CHECK-NEXT: 15.0 1 3{{$}}
// CHECK-NEXT: 1{{$}}

// Clause 5: one sample each of comments, identifier forms, integer, real, time and string literals.
module top;
  int plain_id$1 = 1;  // _ and $ are legal after the first character
  int \a+b = 2;        /* an escaped identifier ends at white space */
  logic [7:0] n = 8'b1x0z_1010;
  logic [15:0] h = 'hAB;
  real r = 1.5e1;
  time t = 2ns;
  string s = "a\tb";
  initial begin
    $display("%0d %0d", plain_id$1, \a+b );
    $display("%b %h", n, h);
    $display("%0.1f %0d %0d", r, t >= 0, s.len());
    $display("%b", 4'b1011 ==? 4'b10?1);
    $finish;
  end
endmodule
