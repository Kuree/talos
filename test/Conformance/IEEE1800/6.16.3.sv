// CLAUSE: string putc and bounds
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 6.16.3: getc returns the byte (0 out of range) and putc replaces one byte, ignoring out-of-range indices and a 0 value.
// CHECK: getc 97 99 0 0
// CHECK: putc aXc

module top;
  string s;
  initial begin
    s = "abc";
    $display("getc %0d %0d %0d %0d", s.getc(0), s.getc(2), s.getc(3), s.getc(-1));
    s.putc(1, "X");  s.putc(3, "Y");  s.putc(-1, "Z");  s.putc(0, 0);
    $display("putc %s", s);
  end
endmodule
