// CLAUSE: parameter override dependent defaults
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 23.10.4.1 steps b/c: the defparam from top is applied before the generate condition is evaluated, and a defparam inside the generated block sets a parameter computed from it.
// CHECK-DAG: LEAF block=g2 N=2
// CHECK-DAG: CHILD M=6

module child #(parameter int M = 1) (); initial $display("CHILD M=%0d", M); endmodule
module leaf #(parameter int N = 1) ();
  if (N == 2) begin : g2
    child c();
    defparam c.M = N * 3;
    initial $display("LEAF block=g2 N=%0d", N);
  end else begin : g1
    initial $display("LEAF block=g1 N=%0d", N);
  end
endmodule
module top;
  leaf u();
  defparam u.N = 2;
endmodule
