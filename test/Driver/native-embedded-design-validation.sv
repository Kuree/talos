// RUN: talos -O1 --vpi=read --dump-ir-after=finalize-native-functions --dump-ir-path=%t.mlir %s -o %t.dump
// RUN: FileCheck %s --implicit-check-not=context_create_for_design < %t.mlir

// A closed native executable whose eval state VPI may read embeds its design
// database. The compiler libraries do not link the runtime: the native driver
// registers the runtime's validator, so the database is validated at compile
// time and the scheduler main creates its context from the embedded copy.
// CHECK: llvm.func @talos_rt_v1_context_create_embedded_read(
// CHECK: llvm.call @talos_rt_v1_context_create_embedded_read(
module native_embedded_design_validation;
  bit clk = 0;
  bit [7:0] count = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) count <= count + 1;
  initial #20 $finish;
endmodule
