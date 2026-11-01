// CLAUSE: always_latch holds its value while the gate is low; a timing control inside is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// CHECK: never opened x{{$}}
// CHECK-NEXT: open d=1 1{{$}}
// CHECK-NEXT: open d=0 0{{$}}
// CHECK-NEXT: open d=1 1{{$}}
// CHECK-NEXT: closed 1{{$}}
// CHECK-NEXT: held 1{{$}}

// 9.2.2.3: q tracks d only with ck high, and keeps its value once ck falls.
module top;
  logic ck = 0, d = 0, q;
  always_latch
    if (ck) q <= d;
  task show(string s);
    #1 $display("%s %b", s, q);
  endtask
  initial begin
    show("never opened");
    ck = 1; d = 1;
    show("open d=1");
    d = 0;
    show("open d=0");
    d = 1;
    show("open d=1");
    ck = 0;
    show("closed");
    d = 0;
    show("held");
    $finish;
  end
endmodule
