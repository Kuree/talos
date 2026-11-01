// CLAUSE: A ref argument aliases the caller variable while the subroutine runs; const ref is read-only
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.2/const.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.2/static.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot assign to read-only variable 'x'
// DIAG: 'ref' arguments can only be used in 'automatic' subroutines
// CHECK: immediate a=5{{$}}
// CHECK-NEXT: concurrent x=9{{$}}
// CHECK-NEXT: after a=9{{$}}
// CHECK-NEXT: queue '{7, 1, 3} sum=11{{$}}
// CHECK-NEXT: outdated e=99 q='{1, 3}
// CHECK-NEXT: queue '{1, 3}

// 13.5.2: writes show in the caller before return, the caller's writes show in the callee, and a write through
// the reference to a deleted queue element is not visible outside.
module top;
  int a = 1;
  int q[$] = {1};
  task automatic see(ref int x);
    x = 5;
    $display("immediate a=%0d", a);
    #2 $display("concurrent x=%0d", x);
  endtask
  function automatic void ins(ref int r[$]);
    r.push_back(3);
    r.insert(0, 7);
  endfunction
  function automatic int sum(const ref int r[$]);
    foreach (r[i]) sum += r[i];
  endfunction
  task automatic outdated(ref int e);
    q.delete(0);
    e = 99;
    $display("outdated e=%0d q=%p", e, q);
  endtask
  initial begin
    fork
      see(a);
      #1 a = 9;
    join
    $display("after a=%0d", a);
    ins(q);
    $display("queue %p sum=%0d", q, sum(q));
    outdated(q[0]);
    $display("queue %p", q);
    $finish;
  end
endmodule
