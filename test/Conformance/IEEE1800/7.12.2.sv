// CLAUSE: Array ordering methods reorder elements in place; ordering an associative array is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.12.2/assoc.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.12.2/reverse_with.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.12.2/shuffle_with.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: unknown built-in method 'sort' on type 'int$[int]'
// DIAG: cannot use 'with' expression with 'reverse'
// DIAG: cannot use 'with' expression with 'shuffle'
// CHECK: '{"world", "sad", "hello"}
// CHECK-NEXT: '{1, 3, 4, 5}
// CHECK-NEXT: '{5, 4, 3, 1}
// CHECK-NEXT: 0 2{{$}}
// CHECK-NEXT: '{5, 4, 3, 1}
// CHECK-NEXT: shuffle 4 13{{$}}
// CHECK-NEXT: '{1, 3, 4, 5}
// CHECK-NEXT: 1 2 3{{$}}
// CHECK-NEXT: 2 3 1{{$}}

// 7.12.2: the clause's examples; shuffle may give any order, so it checks the same elements come back.
module top;
  string s[] = {"hello", "sad", "world"};
  int q[$] = {4, 5, 3, 1};
  int p[$];
  int total = 0;
  struct {byte red, green, blue;} c[3];
  initial begin
    s.reverse;           $display("%p", s);
    q.sort;              $display("%p", q);
    q.rsort;             $display("%p", q);
    q.sort with (item % 3); $display("%0d %0d", q[0] % 3, q[3] % 3);
    q.rsort(x) with (x);    $display("%p", q);
    q.shuffle;
    $display("shuffle %0d %0d", q.size(), q.sum());
    q.sort;              $display("%p", q);
    c[0] = '{3, 1, 9}; c[1] = '{1, 2, 7}; c[2] = '{2, 3, 7};
    c.sort with (item.red);
    $display("%0d %0d %0d", c[0].red, c[1].red, c[2].red);
    c.sort(x) with ({x.blue, x.green});
    $display("%0d %0d %0d", c[0].green, c[1].green, c[2].green);
    $finish;
  end
endmodule
