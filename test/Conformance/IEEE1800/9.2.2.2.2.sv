// CLAUSE: always_comb runs at time zero and follows function reads, unlike always @*; blocking statements rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.2.2/delay.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.2.2/other_driver.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// DIAG: driven by always_comb procedure cannot be written to by any other process
// CHECK: time zero 2 0 11 0{{$}}
// CHECK-NEXT: argument 4 4 12 12{{$}}
// CHECK-NEXT: function read 4 4 22 12{{$}}
// CHECK-NEXT: other process 99{{$}}

// 9.2.2.2.2: the first two bullets show as differing columns, the third as a write that only always @* allows.
module top;
  int a = 1, g = 10;
  int comb_out = 0, star_out = 0, comb_fn = 0, star_fn = 0, shared = 0;
  function automatic int read_g(int x);
    return x + g;
  endfunction
  always_comb comb_out = a * 2;
  always @* star_out = a * 2;
  always_comb comb_fn = read_g(a);
  always @* star_fn = read_g(a);
  always @* shared = a;
  initial begin
    #1 $display("time zero %0d %0d %0d %0d", comb_out, star_out, comb_fn, star_fn);
    a = 2;
    #1 $display("argument %0d %0d %0d %0d", comb_out, star_out, comb_fn, star_fn);
    g = 20;
    #1 $display("function read %0d %0d %0d %0d", comb_out, star_out, comb_fn, star_fn);
    shared = 99;
    $display("other process %0d", shared);
    $finish;
  end
endmodule
