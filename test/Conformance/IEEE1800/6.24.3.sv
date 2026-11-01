// CLAUSE: Bit-stream casts move bits left to right between unpacked and dynamic types; fixed size mismatch rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.24.3/illegal.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.24.3/struct.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.24.3/runtime.sv -o %t.rt.exe
// RUN: %not %t.rt.exe
// DIAG: value of type 'bit[31:0]' cannot be converted to type 'bytes_t'
// DIAG: value of type 'struct{bit[7:0] a, shortint b}' cannot be converted to type 'int'
// CHECK: struct 11 2233 44{{$}}
// CHECK-NEXT: round trip aa223344{{$}}
// CHECK-NEXT: array aa 22 33 44{{$}}
// CHECK-NEXT: dynamic 4 de ef{{$}}
// CHECK-NEXT: greedy 3 03 04{{$}}
// CHECK-NEXT: string 4142{{$}}
// CHECK-NEXT: four state 1000 1x0z{{$}}
// CHECK: bit-stream cast source and destination widths differ

// 6.24.3: item 0 takes the MSBs, a dynamic destination is greedy, and 4-state bits reaching a 2-state part cast to 0.
module top;
  typedef struct {bit [7:0] a; shortint b; byte c;} S;
  typedef byte bytes_t[4];
  typedef byte dyn_t[];
  typedef struct {byte a[$]; bit [7:0] tail;} Q;
  typedef struct {bit [3:0] a; logic [3:0] b;} M;
  S s;
  bytes_t ba;
  dyn_t da;
  Q q;
  M m;
  string str = "AB";
  int i = 32'h11223344;
  typedef bit [15:0] word_t;
  word_t w;
  initial begin
    s = S'(i);
    $display("struct %h %h %h", s.a, s.b, s.c);
    s.a = 8'haa;
    i = int'(s);
    $display("round trip %h", i);
    ba = bytes_t'(i);
    $display("array %h %h %h %h", ba[0], ba[1], ba[2], ba[3]);
    da = dyn_t'(32'hdeadbeef);
    $display("dynamic %0d %h %h", da.size(), da[0], da[3]);
    q = Q'(32'h01020304);
    $display("greedy %0d %h %h", q.a.size(), q.a[2], q.tail);
    w = word_t'(str);
    $display("string %h", w);
    m = M'(8'b1x0z_1x0z);
    $display("four state %b %b", m.a, m.b);
    $finish;
  end
endmodule
