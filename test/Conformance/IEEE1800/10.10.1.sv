// CLAUSE: Unpacked array concatenation composes elements and arrays; replication is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.10.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: no implicit conversion from 'bit[287:0]' to 'int$[1:9]'
// CHECK: '{1, 2, 3}
// CHECK-NEXT: '{4, 5, 6}
// CHECK-NEXT: '{1, 2, 3, 4, 5, 1, 2, 3, 6}
// CHECK-NEXT: '{1, 1, 1, 1, 1, 1, 1, 1, 1}
// CHECK-NEXT: '{1, 2, 3, 4, 5, 6, 7, 8, 9}

// 10.10.1: elements and whole arrays compose in {...}; only '{n{...}} may replicate.
module top;
  typedef int AI3[1:3];
  AI3 A3;
  int A9[1:9];
  initial begin
    A3 = {1, 2, 3};                    $display("%p", A3);
    A3 = '{4, 5, 6};                   $display("%p", A3);
    A3 = '{1, 2, 3};
    A9 = {A3, 4, 5, A3, 6};            $display("%p", A9);
    A9 = '{9{1}};                      $display("%p", A9);
    A9 = {A3, 4, AI3'{5, 6, 7}, 8, 9}; $display("%p", A9);
    $finish;
  end
endmodule
