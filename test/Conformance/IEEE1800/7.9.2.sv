// CLAUSE: delete default min
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 7.9.2: delete(index) removes one entry, deleting a missing index is a silent no-op, delete() empties the array.
// CHECK: num 3 -> 2 -> 2, exists1=1 exists2=0
// CHECK: empty num=0 exists1=0
// CHECK-NOT: warning

module top;
  int a[int];  int n0, n1, n2, n3;
  initial begin
    a[1] = 10; a[2] = 20; a[3] = 30;  n0 = a.num();
    a.delete(2);  n1 = a.num();
    a.delete(99); n2 = a.num();
    $display("num %0d -> %0d -> %0d, exists1=%0d exists2=%0d", n0, n1, n2, a.exists(1), a.exists(2));
    a.delete(); n3 = a.num();
    $display("empty num=%0d exists1=%0d", n3, a.exists(1));
  end
endmodule
