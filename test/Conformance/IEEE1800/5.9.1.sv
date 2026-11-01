// CLAUSE: String escapes produce the listed characters; an illegal hexadecimal escape is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.9.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: invalid hexadecimal number
// CHECK: len=10 10 9 92 34 11 12 7 65 65 98{{$}}
// CHECK-NEXT: len=6 65 50 65 52 7 122{{$}}
// CHECK-NEXT: Humpty Dumpty sat on a wall. \Humpty Dumpty had a great fall.

// 5.9.1: octal takes at most 3 digits and hex at most 2, so the next digit stays a character; \b is just b.
module top;
  string s = "\n\t\\\"\v\f\a\101\x41\b";
  string o = "\1012\x414\7z";
  initial begin
    $write("len=%0d", s.len());
    foreach (s[i]) $write(" %0d", s[i]);
    $display;
    $write("len=%0d", o.len());
    foreach (o[i]) $write(" %0d", o[i]);
    $display;
    $display("Humpty Dumpty sat on a wall. \\\
Humpty Dumpty had a great fall.");
    $finish;
  end
endmodule
