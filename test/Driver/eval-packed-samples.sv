// RUN: talos -O3 --vpi=off --native-scheduler=eval --dump-ir-after=materialize-native-eval-transactions --dump-ir-path=%t.mlir %s -o %t.dump && FileCheck %s --check-prefix=IR < %t.mlir
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.eval && %t.eval > %t.out && FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.two && %t.two > %t.two.out && FileCheck %s < %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -

// IEEE 1800-2023 4.4.2.1 and 16.5.1. Every sampled q precedes the
// blocking update on that same edge. Keep the five valid bits of each
// lane in both planes, including X and Z on the last edge.
// IR-LABEL: llvm.func internal @__talos_sampled_plane_copy_v1(
// IR: llvm.load {{.*}} -> vector<16xi8>
// IR: llvm.mlir.constant(dense<31> : vector<16xi8>)
// IR: llvm.and {{.*}} : vector<16xi8>
// IR: llvm.store {{.*}} : vector<16xi8>, !llvm.ptr
// IR: llvm.store {{.*}} : vector<8xi8>, !llvm.ptr
// CHECK: first 1
// CHECK-NEXT: second 1
// CHECK-NEXT: third 1
module sampled_lane(input bit clk, input logic [4:0] d, output logic [4:0] seen);
  logic [4:0] q = '0;
  always @(posedge clk) q = d;
  sample_q: assert property (@(posedge clk) 1'b1) seen = $sampled(q);
endmodule

module top;
  localparam int Lanes = 24;
  bit clk;
  logic [Lanes-1:0][4:0] data, seen, prior;
  always #5 clk = !clk;
  for (genvar i = 0; i < Lanes; i++)
    sampled_lane u(.clk, .d(data[i]), .seen(seen[i]));
  initial begin
    #1;
    for (int i = 0; i < Lanes; i++) data[i] = 5'(3*i + 1);
    #5 $display("first %0d", seen === '0);
    prior = data;
    for (int i = 0; i < Lanes; i++) data[i] = i[0] ? 5'bz0x11 : 5'(i+7);
    #10 $display("second %0d", seen === prior);
    prior = data;
    data = '0;
    #10 $display("third %0d", seen === prior);
    $finish;
  end
endmodule
