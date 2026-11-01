// CLAUSE: Array assignment pattern keys apply index, then type, then default; duplicate index rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.9.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: assignment pattern has multiple keys for index 0
// CHECK: '{9, 9, 2, 1}
// CHECK-NEXT: '{5, 7, 7}
// CHECK-NEXT: '{2, 2, 2}
// CHECK-NEXT: '{3, 3, 3}
// CHECK-NEXT: '{4, 4, 4}
// CHECK-NEXT: '{'{6, 6, 6}, '{6, 6, 6}}
// CHECK-NEXT: '{'{8, 7, 7}, '{9, 9, 9}}
// CHECK-NEXT: 1 2 5 6{{$}}

// 10.9.1: index keys beat type keys, type keys beat default, and the last of two matching type keys wins.
module top;
  int a[3:0], t[3];
  int n[1:2][1:3];
  struct {int a; time b;} abkey[1:0];
  initial begin
    a = '{0:1, 1:2, default:9};  $display("%p", a);
    t = '{0:5, int:7};           $display("%p", t);
    t = '{int:1, int:2};         $display("%p", t);
    t = '{default:3};            $display("%p", t);
    t = '{3{4}};                 $display("%p", t);
    n = '{2{'{3{6}}}};           $display("%p", n);
    n = '{1:'{1:8, default:7}, default:9}; $display("%p", n);
    abkey = '{'{a:1, b:2}, '{int:5, time:6}};
    $display("%0d %0d %0d %0d", abkey[1].a, abkey[1].b, abkey[0].a, abkey[0].b);
    $finish;
  end
endmodule
