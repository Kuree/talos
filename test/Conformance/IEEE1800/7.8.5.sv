// CLAUSE: Associative arrays take user-defined index types; X indices are invalid, real index types rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.8.5/real.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.8.5/contains_real.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: index type cannot be or contain floating point types
// DIAG: index type cannot be or contain floating point types
// CHECK: queue index num=3{{$}}
// CHECK-NEXT: read 7{{$}}
// CHECK-NEXT: read 8{{$}}
// CHECK-NEXT: empty read 9{{$}}
// CHECK-NEXT: x index num=1 read 0{{$}}
// CHECK-NEXT: null index num=1 read 5{{$}}

// 7.8.5: lookups compare whole index values, an empty or null element stays valid, and an X element makes the index
// invalid, so the write is ignored and the read gets the default.
module top;
  typedef struct {byte B; int I[$];} Unpkt;
  typedef struct {logic [3:0] n;} Four;
  class C;
  endclass
  typedef struct {C h; int v;} H;
  int array_name[Unpkt];
  int four[Four];
  int hn[H];
  Unpkt k;
  Four f;
  H h;
  initial begin
    k.B = 1;
    k.I = {1, 2}; array_name[k] = 7;
    k.I = {1, 3}; array_name[k] = 8;
    k.I = {};     array_name[k] = 9;
    $display("queue index num=%0d", array_name.num());
    k.I = {1, 2}; $display("read %0d", array_name[k]);
    k.I = {1, 3}; $display("read %0d", array_name[k]);
    k.I = {};     $display("empty read %0d", array_name[k]);
    f.n = 4'b0001; four[f] = 1;
    f.n = 4'b1x00; four[f] = 2;
    $display("x index num=%0d read %0d", four.num(), four[f]);
    h.h = null; h.v = 1; hn[h] = 5;
    $display("null index num=%0d read %0d", hn.num(), hn[h]);
    $finish;
  end
endmodule
