// CLAUSE: Array locator methods return matching elements and indices; find without a with clause is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.12.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: 'find' requires 'with' expression for searching
// CHECK: find '{5, 7, 9}
// CHECK-NEXT: find_index '{1, 3}
// CHECK-NEXT: find_first '{3}
// CHECK-NEXT: find_first_index '{1}
// CHECK-NEXT: find_last '{9}
// CHECK-NEXT: find_last_index '{3}
// CHECK-NEXT: min '{3}
// CHECK-NEXT: max '{9}
// CHECK-NEXT: max with '{3}
// CHECK-NEXT: unique '{3, 5, 7, 9}
// CHECK-NEXT: unique_index 4{{$}}
// CHECK-NEXT: item.index '{3}
// CHECK-NEXT: empty 0{{$}}
// CHECK-NEXT: descending first '{3}
// CHECK-NEXT: descending last '{1}
// CHECK-NEXT: assoc '{20}

// 7.12.1: order is unspecified for find and unique, so those sort first; first and last follow the declared range.
module top;
  int a[] = '{5, 3, 7, 3, 9};
  int d[3:1] = '{1, 2, 3};
  int aa[int];
  int q[$];
  initial begin
    q = a.find(x) with (x > 4);             q.sort(); $display("find %p", q);
    q = a.find_index with (item == 3);      q.sort(); $display("find_index %p", q);
    q = a.find_first with (item == 3);      $display("find_first %p", q);
    q = a.find_first_index(y) with (y == 3); $display("find_first_index %p", q);
    q = a.find_last with (item > 6);        $display("find_last %p", q);
    q = a.find_last_index with (item == 3); $display("find_last_index %p", q);
    q = a.min;                              $display("min %p", q);
    q = a.max;                              $display("max %p", q);
    q = a.max with (-item);                 $display("max with %p", q);
    q = a.unique;                           q.sort(); $display("unique %p", q);
    q = a.unique_index(x) with (x);         $display("unique_index %0d", q.size());
    q = a.find with (item == item.index + 2); $display("item.index %p", q);
    q = a.find with (item > 100);           $display("empty %0d", q.size());
    q = d.find_first_index with (item > 0); $display("descending first %p", q);
    q = d.find_last_index with (item > 0);  $display("descending last %p", q);
    aa[10] = 1; aa[20] = 2; aa[30] = 2;
    q = aa.find_first_index with (item == 2); $display("assoc %p", q);
    $finish;
  end
endmodule
