// RUN: talos -O3 --native-scheduler=auto --mlir-timing %s -o %t.auto 2> %t.timing
// RUN: FileCheck %s --check-prefix=PLAN < %t.timing
// RUN: talos -O0 --native-scheduler=generic %s -o %t.generic
// RUN: %t.auto > %t.auto.out
// RUN: %t.generic > %t.generic.out
// RUN: diff -u %t.generic.out %t.auto.out
// RUN: FileCheck %s < %t.auto.out

// A delayed continuous assignment (IEEE 1800-2023 10.3.3) keeps only its own
// process runtime-owned: it evaluates at time zero and after each input
// change, and its inertial update reaches the generated owners that read the
// net as an ordinary publication. The flop and the combinational owner stay in
// the generated plan (two-tier P1e).
module native_delayed_continuous_owners;
  logic clk = 0;
  logic [7:0] a = 0, q = 0, r;
  wire [7:0] d;
  assign #1 d = a + 1;
  always #5 clk = ~clk;
  always_ff @(posedge clk) q <= d;
  always_comb r = q ^ 8'h0f;
  initial begin
    a = 3;
    #12 a = 7;
    #20 $display("q=%0d r=%0d d=%0d", q, r, d);
    $finish;
  end
endmodule

// PLAN: withheld actor: {{.*}}.sv":18:13) reason=delayed continuous assignment is runtime-owned
// PLAN: talos eval executor inventory: tier1=2 tier2=0
// PLAN: talos started owners: admitted=2
// CHECK: q=8 r=7 d=8
