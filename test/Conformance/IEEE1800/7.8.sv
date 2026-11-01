// CLAUSE: Associative arrays store sparse keys and traverse in order; a real index type is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.8/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: index type cannot be or contain floating point types
// CHECK: num 3 3{{$}}
// CHECK-NEXT: a=1{{$}}
// CHECK-NEXT: b=2{{$}}
// CHECK-NEXT: c=3{{$}}
// CHECK-NEXT: -5{{$}}
// CHECK-NEXT: 100{{$}}
// CHECK-NEXT: 1000000{{$}}
// CHECK-NEXT: exists 1 0{{$}}
// CHECK-NEXT: deleted 2 0{{$}}
// CHECK-NEXT: default 7{{$}}

// 7.8: traversal follows index order, not the order of writes, across string and negative integer keys.
module top;
  int a[string];
  int b[int];
  int d[string] = '{default: 7};
  string key;
  int i;
  initial begin
    a["b"] = 2; a["a"] = 1; a["c"] = 3;
    $display("num %0d %0d", a.num(), a.size());
    if (a.first(key)) do $display("%s=%0d", key, a[key]); while (a.next(key));
    b[100] = 1; b[-5] = 2; b[1000000] = 3;
    foreach (b[j]) $display("%0d", j);
    $display("exists %0d %0d", a.exists("a"), a.exists("z"));
    a.delete("a");
    $display("deleted %0d %0d", a.num(), a.exists("a"));
    $display("default %0d", d["nope"]);
    $finish;
  end
endmodule
