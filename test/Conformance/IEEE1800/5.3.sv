// CLAUSE: formfeed tokens
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 5.3: formfeed (as well as blank, tab, newline) is white space that separates tokens, while blanks inside a string literal are kept (length 6, byte 32).
// CHECK: v=5 len=6 sp=32

module top;
  intv=5;
  string s = "a  b\tc";
  initial $display("v=%0d len=%0d sp=%0d", v, s.len(), s[1]);
endmodule
