// CLAUSE: Enums accept cast values and read as integers; assigning an integer directly is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.19.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: no implicit conversion from 'int' to 'Colors'
// CHECK: 1 green{{$}}
// CHECK-NEXT: auto-cast equal{{$}}
// CHECK-NEXT: to int 2{{$}}
// CHECK-NEXT: cast yellow{{$}}
// CHECK-NEXT: out of set 42 []

// 6.19.3: integers enter only by cast, which can hold an out-of-set value, and the enum reads back as an integer.
module top;
  typedef enum {red, green, blue, yellow, white, black} Colors;
  Colors c;
  int i;
  initial begin
    c = green;
    $display("%0d %s", c, c.name());
    if (1 == c) $display("auto-cast equal");
    i = c + 1;
    $display("to int %0d", i);
    c = Colors'(3);
    $display("cast %s", c.name());
    c = Colors'(42);
    $display("out of set %0d [%s]", c, c.name());
    $finish;
  end
endmodule
