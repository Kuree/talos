// CLAUSE: A renamed generate block lets defparam resolve; a name that would re-resolve is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/23.10.4.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: defparam target resolves differently post-elaboration; see 'top.n.p' vs 'top.n.top.n.p'
// CHECK: outer p=1 nested p=3{{$}}

// 23.10.4.2: renaming the generate block is the clause's fix. The generate branch exists only if defparam reached
// parameter p early, and nested p keeps its own value.
module top;
  M n();
endmodule
module M;
  parameter p = 2;
  defparam top.n.p = 1;
  if (p == 1) begin : g
    N n();
  end
  initial begin
    $display("outer p=%0d nested p=%0d", top.n.p, g.n.p);
    $finish;
  end
endmodule
module N;
  parameter p = 3;
endmodule
