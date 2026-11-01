// CLAUSE: Net aliases share bits in both directions; self-alias and mixed net types are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.11/self.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.11/mixed.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot alias a net to itself
// DIAG: all nets in a net alias statement must have a common nettype
// CHECK: a to b 44332211{{$}}
// CHECK-NEXT: b to a ddccbbaa{{$}}
// CHECK-NEXT: w to parts 78 12{{$}}
// CHECK-NEXT: parts to w a5zzzz5a{{$}}

// 10.11: the examples drive one side and read the other, in both directions and through part-selects.
module byte_swap(inout wire [31:0] A, inout wire [31:0] B);
  alias {A[7:0], A[15:8], A[23:16], A[31:24]} = B;
endmodule
module byte_rip(inout wire [31:0] W, inout wire [7:0] LSB, MSB);
  alias W[7:0] = LSB;
  alias W[31:24] = MSB;
endmodule
module top;
  logic [31:0] da = 'z, db = 'z, dw = 'z;
  logic [7:0] dl = 'z, dm = 'z;
  wire [31:0] a = da, b = db, w = dw;
  wire [7:0] lsb = dl, msb = dm;
  byte_swap s(a, b);
  byte_rip r(w, lsb, msb);
  initial begin
    da = 32'h11223344;            #1 $display("a to b %h", b);
    da = 'z; db = 32'haabbccdd;   #1 $display("b to a %h", a);
    dw = 32'h12345678;            #1 $display("w to parts %h %h", lsb, msb);
    dw = 'z; dl = 8'h5a; dm = 8'ha5; #1 $display("parts to w %h", w);
    $finish;
  end
endmodule
