// CLAUSE: break, continue and return control loops and subroutines; rejected outside a loop
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/12.8/break.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/12.8/continue.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/12.8/fork.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statement can only be used inside a loop
// DIAG: statement can only be used inside a loop
// DIAG: statement can only be used inside a loop
// CHECK: for sum=8 last=5{{$}}
// CHECK-NEXT: foreach '{0, 2, 10}
// CHECK-NEXT: return 8 -1{{$}}
// CHECK-NEXT: task return 1{{$}}

// 12.8: break leaves a whole multi-dimensional foreach, and continue still runs the loop control.
module top;
  int sum = 0, last = 0;
  int m[2][3];
  int visits[$];
  function automatic int early(int n);
    for (int i = 0; i < 10; i++)
      if (i == n) return i * 2;
    return -1;
  endfunction
  task automatic stop(output int o);
    o = 1;
    return;
    o = 2;
  endtask
  initial begin
    for (int i = 0; i < 10; i++) begin
      last = i;
      if (i == 2) continue;
      if (i == 5) break;
      sum += i;
    end
    $display("for sum=%0d last=%0d", sum, last);
    foreach (m[i, j]) begin
      if (i == 0 && j == 1) continue;
      if (i == 1 && j == 1) break;
      visits.push_back(10 * i + j);
    end
    $display("foreach %p", visits);
    $display("return %0d %0d", early(4), early(20));
    stop(sum);
    $display("task return %0d", sum);
    $finish;
  end
endmodule
