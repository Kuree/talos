// RUN: talos -O3 --native-scheduler=eval --mlir-timing %s -o %t.eval 2> %t.timing
// RUN: FileCheck %s --check-prefix=PLAN < %t.timing
// RUN: talos -O0 --native-scheduler=generic %s -o %t.generic
// RUN: %t.eval > %t.eval.out
// RUN: %t.generic > %t.generic.out
// RUN: diff -u %t.generic.out %t.eval.out
// RUN: FileCheck %s < %t.eval.out

// Switch control and delayed switch contributions (IEEE 1800-2023 28.8,
// 28.16) keep only the controlling primitives and the drivers of nets the
// runtime resolves runtime-owned. The flops, including the one sampling a
// switch-connected net, stay in the generated plan and are woken by the
// runtime's net publication (two-tier P1e).
module native_switch_owners;
  logic clk = 0;
  logic [7:0] count = 0;
  logic en = 0, drv = 1, sampled, delayed_sampled;
  wire a, b, c;
  always #5 clk = ~clk;
  always_ff @(posedge clk) count <= count + 1;
  assign a = drv;
  tranif1 plain(a, b, en);
  tranif1 #(2) delayed(a, c, en);
  always_ff @(posedge clk) begin
    sampled <= b;
    delayed_sampled <= c;
  end
  always @(b or c) $display("t=%0t b=%b c=%b", $time, b, c);
  initial begin
    #12 en = 1;
    #10 drv = 0;
    #10 en = 0;
    #10 drv = 1;
    #10 $display("count=%0d sampled=%b delayed_sampled=%b", count, sampled,
                 delayed_sampled);
    $finish;
  end
endmodule

// PLAN: withheld actor: {{.*}}reason=switch control is runtime-owned
// PLAN: withheld actor: {{.*}}reason=delayed switch contribution is runtime-owned
// PLAN: withheld actor: {{.*}}reason=net resolution is runtime-owned
// PLAN: talos eval executor inventory: tier1={{[1-9]}} tier2=0
// PLAN: talos started owners: admitted={{[1-9]}}
// CHECK: t=12 b=1 c=z
// CHECK-NEXT: t=14 b=1 c=1
// CHECK-NEXT: t=22 b=0 c=0
// CHECK-NEXT: t=32 b=z c=0
// CHECK-NEXT: t=34 b=z c=z
// CHECK-NEXT: count=5 sampled=z delayed_sampled=z
