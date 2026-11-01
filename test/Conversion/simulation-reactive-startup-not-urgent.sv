// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=generic' | FileCheck %s

// IEEE 1800-2023 4.5: the Reactive region set runs once the Active set is
// quiescent, and 24.3.2 puts a program's port updates and processes in it. Only
// Active-homed actors may start ahead of other queued work. Marking the
// program's port process as a startup actor made it run first, which entered the
// Reactive set before any design process had run.
program P(input bit port);
  initial $display("program");
endprogram
module top;
  bit source = 0;
  P p(source);
  initial $display("design");
endmodule

// The first i32 of a spawn plan is its flags: home region << 1 | initial (16) |
// startup (32).

// The program's port process has Reactive (4) home and no startup bit.
// CHECK-LABEL: llvm.mlir.global internal constant @unit_3.__talos_spawn_plan
// CHECK-NOT: : i32)
// CHECK: llvm.mlir.constant(8 : i32)

// The design's initial process has Active home and starts first.
// CHECK-LABEL: llvm.mlir.global internal constant @unit_2.__talos_spawn_plan
// CHECK-NOT: : i32)
// CHECK: llvm.mlir.constant(48 : i32)

// The program's initial process has Reactive home and no startup bit.
// CHECK-LABEL: llvm.mlir.global internal constant @unit_1.__talos_spawn_plan
// CHECK-NOT: : i32)
// CHECK: llvm.mlir.constant(24 : i32)
