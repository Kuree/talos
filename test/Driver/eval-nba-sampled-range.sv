// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t && %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval --dump-ir-before=materialize-native-eval-transactions --dump-ir-path=%t.mlir %s -o %t.dump && FileCheck %s --check-prefix=VIEW < %t.mlir

module top;
  bit clk, mismatch;
  logic [64:0] q = '0;
  logic [85:0] data;
  localparam logic [72:0] expected = {1'b1, 4'bz01x, 64'h0123456789abcdef, 4'bx0z1};
  int passes, failures;
  always #5 clk = !clk;
  always @(posedge clk) begin
    data = '1;
    q <= {1'b1, 63'b0, 1'b1};
    q <= '0;
  end
  always @(posedge (q[64] != q[0])) mismatch = 1;
  sampled_range: assert property (@(posedge clk)
      $sampled(data[75:3]) === expected &&
      $sampled(data[85:83]) === 3'bx0z)
    passes++; else failures++;
  initial begin
    data[75:3] = expected;
    data[85:83] = 3'bx0z;
    #6 $display("before mismatch=%b q=%017h passes=%0d failures=%0d", mismatch, q, passes, failures);
    q <= 65'd1;
    #1 $display("after mismatch=%b q=%017h", mismatch, q);
    $finish;
  end
endmodule
// CHECK: before mismatch=0 q=00000000000000000 passes=1 failures=0
// CHECK-NEXT: after mismatch=1 q=00000000000000001
// VIEW: llvm.call @talos_rt_v1_sampled_plane(
// VIEW: llvm.call @talos_rt_v1_sampled_plane(
// VIEW: llvm.load {{.*}} {alignment = 1 : i64} : !llvm.ptr -> i80
// VIEW: llvm.load {{.*}} {alignment = 1 : i64} : !llvm.ptr -> i80
// VIEW: llvm.call @talos_rt_v1_sampled_read(
