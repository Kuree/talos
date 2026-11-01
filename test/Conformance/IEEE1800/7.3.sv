// CLAUSE: untagged union storage and its dynamic member rule
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: forbids dynamic and chandle types in an untagged union
// CHECK: bits=ffffffff
// CHECK: value=1
// CHECK: text=hello

// 7.3: a union is one piece of storage accessed through any member, and dynamic
// and chandle types can be used only in a tagged union.
module top;
  typedef union packed { int value; bit [31:0] bits; } U;
  typedef union tagged { int value; string text; } T;
  U u;
  T t;
  initial begin
    u.value = -1;
    $display("bits=%h", u.bits);
    u.bits = 32'd1;
    $display("value=%0d", u.value);
    t = tagged text "hello";
    $display("text=%s", t.text);
    $finish;
  end
endmodule
