// CLAUSE: String literals fill integrals right-justified and quoted forms span lines; an open string is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.9/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: missing closing quote
// CHECK: 41 0a{{$}}
// CHECK-NEXT: 48656c6c6f20776f726c640a{{$}}
// CHECK-NEXT: 000048656c6c6f20776f726c640a{{$}}
// CHECK-NEXT: cd{{$}}
// CHECK-NEXT: Humpty Dumpty sat on a wall. Humpty Dumpty had a great fall.
// CHECK-NEXT: Humpty Dumpty sat on a "wall".
// CHECK-NEXT: Humpty Dumpty had a great fall.
// CHECK-NEXT: Humpty Dumpty{{$}}
// CHECK-NEXT: sat{{$}}

// 5.9: integrals pad and truncate on the left; the backslash-newline joins lines in both quoted forms.
module top;
  byte c1 = "A";
  bit [7:0] d = "\n";
  bit [8*12:1] stringvar = "Hello world\n";
  bit [8*14:1] wide = "Hello world\n";
  bit [8*2:1] narrow = "abcd";
  initial begin
    $display("%h %h", c1, d);
    $display("%h", stringvar);
    $display("%h", wide);
    $display("%s", narrow);
    $display("Humpty Dumpty sat on a wall. \
Humpty Dumpty had a great fall.");
    $display("""Humpty Dumpty sat on a "wall".
Humpty Dumpty had a great fall.""");
    $display("""Humpty \
Dumpty\nsat""");
    $finish;
  end
endmodule
