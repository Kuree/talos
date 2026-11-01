// CLAUSE: Comment forms hide text exactly as specified; an unterminated block comment is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.4/unterminated.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.4/nested.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: block comment unclosed at end of file
// DIAG: nested block comments are disallowed by SystemVerilog
// CHECK: a=205{{$}}

// 5.4: 205 is 1+4+8+64+128; each hidden assignment would change it.
module top;
  int a = 0;
  initial begin
    a += 1;      // a += 2; /* a block opener has no meaning here
    a += 4;      /* a line comment token // has no meaning here */ a += 8;
    /* a += 16;
       a += 32; */ a += 64;
    a += /* inside an expression */ 128;
    $display("a=%0d", a);
    $finish;
  end
endmodule
