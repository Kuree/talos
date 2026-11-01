// CLAUSE: always_comb triggers at time zero and on input changes; a timing control inside is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.2/delay.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.2/other_driver.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// DIAG: driven by always_comb procedure cannot be written to by any other process
// CHECK: time zero 1 5 1 1{{$}}
// CHECK-NEXT: c falls 0 1 0{{$}}
// CHECK-NEXT: swap 0 0 1{{$}}
// CHECK-NEXT: both 1 1 1{{$}}

// 9.2.2.2: k = 5 has no inputs and runs only through the time zero trigger; independent elements may have separate
// procedures.
module top;
  logic b = 1, c = 1, a;
  int k = 0;
  logic arr[2];
  always_comb a = b & c;
  always_comb k = 5;
  always_comb arr[0] = b;
  always_comb arr[1] = c;
  initial begin
    #1 $display("time zero %b %0d %b %b", a, k, arr[0], arr[1]);
    c = 0;
    #1 $display("c falls %b %b %b", a, arr[0], arr[1]);
    b = 0; c = 1;
    #1 $display("swap %b %b %b", a, arr[0], arr[1]);
    b = 1;
    #1 $display("both %b %b %b", a, arr[0], arr[1]);
    $finish;
  end
endmodule
